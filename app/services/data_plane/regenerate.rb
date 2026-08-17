module DataPlane
  # Regenerates the static index. Cheap at Omarchy's scale — the whole index
  # can be rebuilt on every publish (the crates.io degenerate case).
  class Regenerate
    # A per-plugin trigger still rebuilds everything (cheap at this scale) —
    # writing the one index first and then rewriting it under a second
    # generation would just churn two generations for one publish.
    def self.plugin(_plugin)
      all
    end

    def self.all
      generator = new
      # Reconciliation FIRST: revocations recorded on the surviving data plane
      # are re-learned and ENFORCED before anything is signed, so every file
      # written below reflects post-takedown state.
      generator.reconcile_disk_revocations!
      generator.write_config
      generator.write_revocations
      # Artifacts BEFORE any index that promises them — including all.json
      Plugin.find_each do |p|
        generator.restore_missing_tarballs(p)
        generator.write_plugin_index(p)
      end
      generator.write_all_listing
    end

    # Full regeneration must be able to rebuild the ENTIRE data plane from the
    # database — indexes that reference tarballs the directory doesn't hold
    # would 404 (or worse, a sync --delete would drop survivors).
    def restore_missing_tarballs(plugin)
      plugin.versions.where(state: [ :published, :yanked ]).find_each do |version|
        next if DataPlane.root.join(version.tarball_path).exist?
        next unless version.tarball.attached?
        bytes = version.tarball.download
        # A stored blob that no longer matches the signed checksum must never
        # be served — skip loudly, don't freeze corruption
        unless Digest::SHA256.hexdigest(bytes) == version.sha256
          Rails.logger.error("[DataPlane] checksum mismatch restoring #{version.tarball_path} — skipped")
          next
        end
        DataPlane.freeze_tarball(version, bytes)
      end
    end

    # Freshness horizons: signed files carry generated_at/expires_at so a
    # stale or rolled-back CDN/object-store copy stops verifying. The kill
    # list regenerates every 10 minutes and expires fastest — clients fail
    # CLOSED on an expired revocation list.
    REVOCATIONS_TTL = 24.hours
    INDEX_TTL = 7.days

    # One strictly-increasing generation per regeneration run: clients order
    # signed files by this integer. Anchored to wall-clock milliseconds so a
    # database restore can't re-issue generations clients already saw, while
    # the counter guarantees strict increase even within one millisecond.
    def generation
      @generation ||= RegistryCounter.next!("data_plane_generation",
        floor: (Time.current.to_f * 1000).to_i)
    end

    def freshness(ttl)
      { "generation" => generation,
        "generated_at" => Time.current.utc.iso8601,
        "expires_at" => ttl.from_now.utc.iso8601 }
    end

    def write_config
      # The public key is served unsigned (trust root — clients pin it);
      # everything else carries a detached .sig made with this key. A CHANGED
      # key aborts regeneration outright: an accidental seed swap must never
      # silently replace the trust root and strand every pinned client.
      key_path = DataPlane.root.join("signing-key.pub")
      FileUtils.mkdir_p(DataPlane.root)
      if key_path.exist? && key_path.read != Signer.public_key_base64 &&
          ENV["REGISTRY_ALLOW_KEY_ROTATION"] != "1"
        raise "signing key changed since the data plane was written — refusing to replace the trust root " \
              "(set REGISTRY_ALLOW_KEY_ROTATION=1 only for a deliberate, announced rotation)"
      end
      # Atomic, and only when it actually changed — a recurring rewrite must
      # never risk a truncated trust root
      unless key_path.exist? && key_path.read == Signer.public_key_base64
        DataPlane.atomic_write("signing-key.pub", Signer.public_key_base64)
      end

      DataPlane.write("config.json", JSON.pretty_generate({
        "dl" => "#{DataPlane.base_url}/dl/{publisher}/{name}/{name}-{version}.tar.gz",
        "index" => "#{DataPlane.base_url}/index/{publisher}/{name}.json",
        "revocations" => "#{DataPlane.base_url}/revocations.json",
        "signing_key" => "#{DataPlane.base_url}/signing-key.pub",
        "api" => DataPlane.base_url
      }.merge(freshness(INDEX_TTL))))
    end

    # One JSON line per version, append-only in spirit: every version ever
    # created appears; only published/yanked are useful to clients, and yanked
    # versions stay listed (with the flag) for reproducibility. The first line
    # is a meta record carrying the freshness horizon.
    def write_plugin_index(plugin)
      lines = [ JSON.generate({ "meta" => true }.merge(freshness(INDEX_TTL))) ]
      plugin.versions.where(state: [ :published, :yanked ]).order(:version_sort_key).each do |v|
        # A published version whose bytes are unrecoverable must not be
        # promised by a freshly signed index — flag it loudly instead.
        if v.published? && !DataPlane.root.join(v.tarball_path).exist?
          Rails.logger.error("[DataPlane] #{v.tarball_path} unrecoverable — omitted from signed index")
          AuditEvent.record!(action: "version.artifact_unrecoverable", subject: v,
            metadata: { plugin: plugin.full_name, version: v.version })
          next
        end
        lines << JSON.generate(version_entry(v))
      end
      DataPlane.write("index/#{plugin.publisher.name}/#{plugin.name}.json", lines.join("\n") + "\n")
    end

    def write_all_listing
      plugins = Plugin.listed.includes(:publisher).filter_map do |plugin|
        next unless plugin.latest_version
        {
          "publisher" => plugin.publisher.name,
          "name" => plugin.name,
          "id" => plugin.manifest_id,
          "summary" => plugin.summary,
          "kinds" => plugin.kinds,
          "latest" => plugin.latest_version,
          "downloads" => plugin.downloads_count
        }
      end
      DataPlane.write("all.json", JSON.generate({ "plugins" => plugins }.merge(freshness(INDEX_TTL))))
    end

    # The kill list is append-critical: the union of database revocations and
    # any orphan entries preserved from the on-disk file (plugins the restored
    # database no longer knows still stay revoked — a signed revocation is
    # never erased just because a backup predates its plugin row).
    def write_revocations
      entries = Revocation.includes(plugin: :publisher).order(:created_at).map(&:as_kill_list_entry)
      known = entries.map { |e| [ e["plugin"], e["version"] ] }.to_set
      orphans = (@orphan_revocations || []).reject { |e| known.include?([ e["plugin"], e["version"] ]) }
      DataPlane.write("revocations.json", JSON.pretty_generate(
        { "schemaVersion" => 1, "revocations" => entries + orphans }.merge(freshness(REVOCATIONS_TTL))))
    end

    # A database restored from a pre-revocation backup re-learns every signed
    # on-disk revocation AND re-applies its effects: versions yank, whole-plugin
    # revocations security-hold, in-flight work stops, latest refreshes.
    def reconcile_disk_revocations!
      @orphan_revocations = []
      path = DataPlane.root.join("revocations.json")
      return unless path.exist?
      content = path.read
      signature = DataPlane.root.join("revocations.json.sig")
      return unless signature.exist? && Signer.verify?(content, signature.read)

      import_revocation_entries(JSON.parse(content).fetch("revocations", []))
    rescue JSON::ParserError
      nil
    end

    # Idempotent, enforcement-first: every entry is re-ENFORCED on every run
    # (a crash between row creation and enforcement heals on the next pass),
    # and the row is created only after enforcement held. Shared with
    # registry:import_revocations for recovery from any surviving signed copy.
    def import_revocation_entries(entries)
      @orphan_revocations ||= []
      entries.each do |entry|
        publisher_name, plugin_name = entry["plugin"].to_s.split(".", 2)
        plugin = Plugin.joins(:publisher).find_by(publishers: { name: publisher_name }, name: plugin_name)
        if plugin.nil?
          # The restored DB predates this plugin — its revocation survives in
          # the kill list verbatim rather than being silently erased
          @orphan_revocations << entry.slice("plugin", "version", "reason", "revoked_at")
          next
        end
        reason = entry["reason"].presence || "restored from data plane"
        enforce_revocation!(plugin, entry["version"], reason)
        next if Revocation.exists?(plugin:, version: entry["version"])
        Revocation.create!(plugin:, version: entry["version"], reason:,
          created_by: Registry::SeedCatalog.system_user)
        AuditEvent.record!(action: "revocation.reimported", subject: plugin, public: true,
          metadata: { plugin: entry["plugin"], version: entry["version"] })
      end
    end

    def enforce_revocation!(plugin, version_string, reason)
      system_user = Registry::SeedCatalog.system_user
      if version_string.present?
        version = plugin.versions.find_by(version: version_string)
        return if version.nil? || version.yanked? || version.rejected? # already enforced
        if version.published?
          version.yank!(reason:, actor: system_user)
        else
          version.update!(state: :yanked, yanked_at: Time.current, yank_reason: reason)
        end
      else
        plugin.update!(state: :security_holding, latest_version: nil) unless plugin.security_holding?
        plugin.versions.published.find_each { |v| v.yank!(reason:, actor: system_user) }
        plugin.versions.where(state: [ :processing, :held, :quarantined ], published_at: nil)
          .update_all(state: PluginVersion.states[:rejected], review_notes: "revocation restored: #{reason}")
        plugin.versions.where(state: [ :processing, :held, :quarantined ]).where.not(published_at: nil)
          .update_all(state: PluginVersion.states[:yanked], yanked_at: Time.current, yank_reason: reason)
      end
      plugin.refresh_latest_version!
    end

    private

    def version_entry(version)
      {
        "id" => version.plugin.manifest_id,
        "vers" => version.version,
        "sha256" => version.sha256,
        "size" => version.size_bytes,
        "yanked" => version.yanked?,
        "license" => version.license,
        "minOmarchyVersion" => version.min_omarchy_version,
        "kinds" => version.manifest["kinds"],
        "caps" => version.capability_fingerprint
      }.compact
    end
  end
end
