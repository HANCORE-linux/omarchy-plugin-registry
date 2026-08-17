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

    def initialize(user:, publisher:, plugin_name:, tarball_bytes:, token: nil)
      @user = user
      @publisher = publisher
      @plugin_name = plugin_name
      @tarball_bytes = tarball_bytes
      @token = token
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
      fail! "namespace is unclaimed — prove control of the source repo to claim it", status: :forbidden unless publisher.claimed?
      fail! "you are not a member of #{publisher.name}", status: :forbidden unless user.member_of?(publisher)
      fail! "enable two-factor authentication to publish", status: :forbidden unless user.otp_enabled?
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

    def find_or_build_plugin!
      @plugin = publisher.plugins.find_by(name: plugin_name)
      if plugin.nil?
        @plugin = publisher.plugins.new(name: plugin_name)
        fail! plugin.errors.full_messages.join("; ") unless plugin.valid?
      elsif !plugin.active?
        fail! "#{plugin.full_name} is #{plugin.state.humanize.downcase} and cannot accept new versions", status: :forbidden
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

    def create_version!
      ApplicationRecord.transaction do
        plugin.save! unless plugin.persisted?
        plugin.update!(
          summary: tarball.manifest["description"].presence || plugin.summary,
          kinds: tarball.manifest["kinds"],
          repository_url: tarball.manifest["repository"].presence || plugin.repository_url,
          readme: tarball.readme.presence || plugin.readme
        )
        @version = plugin.versions.create!(
          version: tarball.manifest["version"],
          manifest: tarball.manifest,
          sha256: tarball.sha256,
          size_bytes: tarball.size_bytes,
          license: tarball.manifest["license"],
          min_omarchy_version: tarball.manifest["minOmarchyVersion"],
          state: :published,
          published_at: Time.current
        )
        DataPlane.freeze_tarball(version, tarball_bytes)
        plugin.refresh_latest_version!
        AuditEvent.record!(actor: user, action: "version.publish", subject: version, public: true,
          metadata: { plugin: plugin.full_name, version: version.version, sha256: version.sha256 })
      end
      DataPlane::RegenerateJob.perform_later(plugin)
    end

    def fail!(message, status: :unprocessable_entity)
      raise PublishError.new(message, status:)
    end
  end
end
