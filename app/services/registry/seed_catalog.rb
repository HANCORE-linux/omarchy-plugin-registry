module Registry
  # Seeds plugins from the omarchyplugins.com catalog: each entry becomes an
  # UNCLAIMED publisher + a snapshot of the listed repo pushed through the full
  # review pipeline like any publish. Claiming a seeded namespace requires
  # one-time proof of control of the source repo (Registry::RepoProof).
  #
  # Entry shape: { "publisher" => "ryanrhughes", "name" => "weather",
  #   "summary" => "...", "repository" => "https://github.com/..." }
  class SeedCatalog
    SYSTEM_EMAIL = "registry@omarchy.org".freeze

    # Permanently suspended: the system identity exists only as a provenance
    # marker for seeded versions and can never sign in interactively.
    def self.system_user
      User.find_or_create_by!(email_address: SYSTEM_EMAIL) do |u|
        u.name = "Omarchy Registry"
        u.suspended_at = Time.current
      end
    end

    def self.import(entries, snapshotter: RepoSnapshot.method(:tarball_for))
      entries.map do |entry|
        import_entry(entry, snapshotter:)
      end
    end

    def self.import_entry(entry, snapshotter:)
      # The claim-proof target must belong to the seeded namespace: the repo
      # owner segment has to match the publisher, or a mismatched catalog row
      # would make one person's namespace claimable through another's repo.
      owner = entry["repository"].to_s[%r{\Ahttps://[^/]+/([^/]+)/}, 1].to_s.downcase
      unless owner == entry.fetch("publisher").to_s.downcase
        return { entry:, status: "failed", reason: "repository owner #{owner.inspect} does not match publisher" }
      end

      publisher = Publisher.find_or_create_by!(name: entry.fetch("publisher")) do |p|
        p.kind = :personal
        p.claimed = false
        p.seed_source_url = entry["repository"]
      end
      # Never seed into a namespace someone already owns — a squatter who
      # claimed the name first must not receive the legitimate artifact under
      # their identity. Authors with several repos are fine: the publisher's
      # seed_source_url (their first listed repo) is only the claim-proof
      # target; each plugin keeps its own repository in its manifest.
      if publisher.claimed?
        return { entry:, status: "skipped", reason: "namespace already claimed" }
      end
      return { entry:, status: "skipped", reason: "already published" } if
        publisher.plugins.find_by(name: entry.fetch("name"))&.versions&.exists?

      bytes = snapshotter.call(entry.fetch("repository"))
      version = PublishVersion.new(
        user: system_user, publisher:, plugin_name: entry.fetch("name"),
        tarball_bytes: bytes, system_seed: true
      ).call
      AuditEvent.record!(action: "plugin.seed", subject: version.plugin, public: true,
        metadata: { plugin: version.plugin.full_name, source: entry["repository"] })
      { entry:, status: "submitted", version: version.version }
    rescue PublishVersion::PublishError, RepoSnapshot::SnapshotError => e
      # A legacy plugin whose snapshot fails validation must remain VISIBLE and
      # uninstallable, not silently vanish from the directory it came from.
      placeholder_plugin(entry, e.message)
      { entry:, status: "failed", reason: e.message }
    rescue KeyError => e
      { entry:, status: "failed", reason: e.message }
    end

    def self.placeholder_plugin(entry, reason)
      publisher = Publisher.find_by(name: entry["publisher"])
      return if publisher.nil? || publisher.claimed?
      plugin = publisher.plugins.find_or_create_by!(name: entry["name"]) do |p|
        p.summary = entry["summary"]
        p.state = :quarantined
      end
      AuditEvent.record!(action: "plugin.seed_failed", subject: plugin, public: true,
        metadata: { plugin: plugin.full_name, source: entry["repository"], reason: reason.first(300) })
    rescue ActiveRecord::RecordInvalid
      nil
    end
  end
end
