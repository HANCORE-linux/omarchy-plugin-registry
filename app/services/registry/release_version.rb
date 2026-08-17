module Registry
  # The go-live step: freeze the exact reviewed bytes to the data plane,
  # mark published, regenerate the index. Reviewed bytes are executed bytes.
  class ReleaseVersion
    def self.call(version, actor: nil)
      raise ArgumentError, "cannot release a #{version.state} version" unless version.releasable?
      raise ArgumentError, "cannot release into a #{version.plugin.state} plugin" unless version.plugin.active?
      # Suspension or membership loss between submit and release must stop the
      # release — the hold window exists precisely for this.
      raise ArgumentError, "publisher is suspended" if version.plugin.publisher.suspended?
      if (submitter = version.user)
        raise ArgumentError, "submitter is suspended" if submitter.suspended_at.present?
        unless submitter == Registry::SeedCatalog.system_user || submitter.member_of?(version.plugin.publisher)
          raise ArgumentError, "submitter is no longer a member of #{version.plugin.publisher.name}"
        end
      end

      bytes = version.tarball.download
      raise "tarball checksum mismatch at release" unless Digest::SHA256.hexdigest(bytes) == version.sha256

      ApplicationRecord.transaction do
        version.update!(state: :published, published_at: Time.current, hold_until: nil)
        DataPlane.freeze_tarball(version, bytes)
        # refresh_latest_version! also applies page metadata from whichever
        # version is now the latest published one — only cleared code ever
        # shapes the public page.
        version.plugin.refresh_latest_version!
        AuditEvent.record!(actor:, action: "version.publish", subject: version, public: true,
          metadata: { plugin: version.plugin.full_name, version: version.version, sha256: version.sha256 })
      end
      DataPlane::RegenerateJob.perform_later(version.plugin)
      version
    end
  end
end
