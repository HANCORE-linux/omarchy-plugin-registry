module Registry
  # The publish pipeline, Phase 1 shape: authorize → inspect → validate →
  # freeze → index. Scanning (Phase 2) slots in between validate and freeze
  # behind the same API without touching clients.
  class PublishVersion
    class PublishError < StandardError
      attr_reader :status
      def initialize(message, status: :unprocessable_entity)
        super(message)
        @status = status
      end
    end

    attr_reader :version

    # system_seed skips membership/MFA/claim checks — used ONLY by the seed
    # importer; seeded versions still run the full review pipeline.
    def initialize(user:, publisher:, plugin_name:, tarball_bytes:, token: nil, system_seed: false)
      @user = user
      @publisher = publisher
      @plugin_name = plugin_name
      @tarball_bytes = tarball_bytes
      @token = token
      @system_seed = system_seed
    end

    def call
      authorize!
      inspect_tarball!
      find_or_build_plugin!
      check_version!
      validate_manifest!
      create_version!
      version
    end

    private

    attr_reader :user, :publisher, :plugin_name, :tarball_bytes, :token, :plugin, :tarball

    def authorize!
      fail! "publisher is suspended", status: :forbidden if publisher.suspended?
      fail! "account is suspended", status: :forbidden if user.suspended_at.present?
      return if @system_seed
      fail! "namespace is unclaimed — prove control of the source repo to claim it", status: :forbidden unless publisher.claimed?
      fail! "you are not a member of #{publisher.name}", status: :forbidden unless user.member_of?(publisher)
      fail! "add a passkey or enable two-factor authentication to publish", status: :forbidden unless user.second_factor?
      fail! "publishing is paused after a recent account change — try again later", status: :forbidden if user.in_publish_cooldown?
      if token && !token.authorizes?(publisher, plugin_name)
        fail! "token is not scoped to #{publisher.name}/#{plugin_name}", status: :forbidden
      end
    end

    def inspect_tarball!
      @tarball = TarballInspector.inspect_bytes(tarball_bytes)
    rescue TarballInspector::InvalidTarball => e
      fail! e.message
    end

    # A quarantined plugin whose only history is seed failure/rejection is a
    # placeholder: once the namespace is claimed, its owner can publish a
    # corrected version and the plugin reactivates — but only AFTER the new
    # submission passes validation (see create_version!).
    def find_or_build_plugin!
      @plugin = publisher.plugins.find_by(name: plugin_name)
      if plugin.nil?
        @plugin = publisher.plugins.new(name: plugin_name)
        fail! plugin.errors.full_messages.join("; ") unless plugin.valid?
      elsif plugin.quarantined? && plugin.versions.where.not(state: :rejected).none?
        @reactivate_placeholder = true
      elsif !plugin.active?
        fail! "#{plugin.full_name} is #{plugin.state.humanize.downcase} and cannot accept new versions", status: :forbidden
      end
      check_submission_limits!
    end

    # Resource brakes: unbounded submissions would retain 10MB each and flood
    # the review queue. Publisher-wide limits apply to FIRST submissions too —
    # new plugin names are not an exemption.
    MAX_PENDING_PER_PLUGIN = 5
    MAX_SUBMISSIONS_PER_DAY = 12
    MAX_PUBLISHER_SUBMISSIONS_PER_DAY = 30
    MAX_USER_SUBMISSIONS_PER_DAY = 40
    MAX_PLUGINS_PER_PUBLISHER = 100

    def check_submission_limits!
      return if @system_seed

      # Per-ACCOUNT ceiling: creating extra orgs must not multiply quota
      user_daily = PluginVersion.where(user: user, created_at: 24.hours.ago..).count
      if user_daily >= MAX_USER_SUBMISSIONS_PER_DAY
        fail! "account-wide publish rate limit reached (#{MAX_USER_SUBMISSIONS_PER_DAY}/day)", status: :too_many_requests
      end

      publisher_daily = PluginVersion.joins(:plugin)
        .where(plugins: { publisher_id: publisher.id }, created_at: 24.hours.ago..).count
      if publisher_daily >= MAX_PUBLISHER_SUBMISSIONS_PER_DAY
        fail! "publisher-wide publish rate limit reached (#{MAX_PUBLISHER_SUBMISSIONS_PER_DAY}/day)", status: :too_many_requests
      end
      if !plugin.persisted? && publisher.plugins.count >= MAX_PLUGINS_PER_PUBLISHER
        fail! "publisher has reached the #{MAX_PLUGINS_PER_PUBLISHER}-plugin limit", status: :too_many_requests
      end
      return unless plugin.persisted?

      if plugin.versions.where(state: [ :processing, :held, :quarantined ]).count >= MAX_PENDING_PER_PLUGIN
        fail! "too many versions awaiting review for #{plugin.full_name} — wait for the pipeline or the admin queue", status: :too_many_requests
      end
      if plugin.versions.where(created_at: 24.hours.ago..).count >= MAX_SUBMISSIONS_PER_DAY
        fail! "publish rate limit reached for #{plugin.full_name} (#{MAX_SUBMISSIONS_PER_DAY}/day)", status: :too_many_requests
      end
    end

    def check_version!
      candidate = tarball.manifest["version"].to_s
      fail! "manifest version must be strict semver (got #{candidate})" unless Semver.valid?(candidate)

      if plugin.persisted?
        fail! "#{plugin.full_name}@#{candidate} already exists — versions are immutable", status: :conflict if plugin.version_burned?(candidate)
        if (highest = plugin.highest_version) && Semver.parse(candidate) <= highest.semver
          fail! "version #{candidate} must be greater than #{highest.version}"
        end
      end
    end

    def validate_manifest!
      validator = ManifestValidator.new(manifest: tarball.manifest, publisher:, plugin_name:, tarball:)
      fail! validator.errors.join("; ") unless validator.valid?
    end

    # Structural validation is synchronous (instant CLI feedback); everything
    # judgment-shaped runs in the ReviewJob pipeline. The version lands in
    # `processing` and goes live only after scan + hold.
    def create_version!
      # Public plugin metadata (summary/kinds/repo/readme) is NOT touched here —
      # ReleaseVersion applies it when a version actually clears review, so a
      # rejected update can never deface the live page.
      ApplicationRecord.transaction do
        plugin.save! unless plugin.persisted?
        plugin.update!(state: :active) if @reactivate_placeholder
        @version = plugin.versions.create!(
          user: user,
          version: tarball.manifest["version"],
          manifest: tarball.manifest,
          sha256: tarball.sha256,
          size_bytes: tarball.size_bytes,
          license: tarball.manifest["license"],
          min_omarchy_version: tarball.manifest["minOmarchyVersion"],
          provenance: token&.provenance,
          state: :processing
        )
        version.tarball.attach(
          io: StringIO.new(tarball_bytes),
          filename: version.tarball_filename,
          content_type: "application/gzip"
        )
        AuditEvent.record!(actor: user, action: "version.submit", subject: version,
          metadata: { plugin: plugin.full_name, version: version.version, sha256: version.sha256 })
      end
      ReviewJob.perform_later(version)
    rescue ActiveRecord::RecordNotUnique
      # Two concurrent publishes of the same version: the loser gets the same
      # answer a sequential attempt would
      fail! "#{plugin.full_name}@#{tarball.manifest['version']} already exists — versions are immutable", status: :conflict
    end

    def fail!(message, status: :unprocessable_entity)
      raise PublishError.new(message, status:)
    end
  end
end
