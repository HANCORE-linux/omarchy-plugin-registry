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

    def self.system_user
      User.find_or_create_by!(email_address: SYSTEM_EMAIL) { |u| u.name = "Omarchy Registry" }
    end

    def self.import(entries, snapshotter: RepoSnapshot.method(:tarball_for))
      entries.map do |entry|
        import_entry(entry, snapshotter:)
      end
    end

    def self.import_entry(entry, snapshotter:)
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
    rescue PublishVersion::PublishError, RepoSnapshot::SnapshotError, KeyError => e
      { entry:, status: "failed", reason: e.message }
    end
  end
end
