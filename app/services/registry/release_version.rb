module Registry
  # The go-live step: freeze the exact reviewed bytes to the data plane,
  # mark published, regenerate the index. Reviewed bytes are executed bytes.
  class ReleaseVersion
    def self.call(version, actor: nil)
      raise ArgumentError, "cannot release a #{version.state} version" unless version.releasable?

      bytes = version.tarball.download
      raise "tarball checksum mismatch at release" unless Digest::SHA256.hexdigest(bytes) == version.sha256

      ApplicationRecord.transaction do
        version.update!(state: :published, published_at: Time.current, hold_until: nil)
        DataPlane.freeze_tarball(version, bytes)
        version.plugin.refresh_latest_version!
        apply_plugin_metadata(version, bytes)
        AuditEvent.record!(actor:, action: "version.publish", subject: version, public: true,
          metadata: { plugin: version.plugin.full_name, version: version.version, sha256: version.sha256 })
      end
      DataPlane::RegenerateJob.perform_later(version.plugin)
      version
    end

    # Page metadata comes only from versions that cleared review, and only when
    # this version is (now) the latest published one.
    def self.apply_plugin_metadata(version, bytes)
      plugin = version.plugin
      return unless plugin.latest_version == version.version
      readme = TarballInspector.inspect_bytes(bytes).readme
      plugin.update!(
        summary: version.manifest["description"].presence || plugin.summary,
        kinds: version.manifest["kinds"],
        repository_url: version.manifest["repository"].presence || plugin.repository_url,
        readme: readme.presence || plugin.readme
      )
    end
  end
end
