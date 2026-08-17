module Registry
  # The go-live step: freeze the exact reviewed bytes to the data plane,
  # mark published, regenerate the index. Reviewed bytes are executed bytes.
  class ReleaseVersion
    def self.call(version, actor: nil)
      # All authorization gates re-run under the row lock so a concurrent
      # takedown can't slip between check and publish
      version.with_lock { locked_call(version, actor:) }
    end

    def self.locked_call(version, actor:)
      raise ArgumentError, "cannot release a #{version.state} version" unless version.releasable?
      if Revocation.exists?(plugin: version.plugin, version: version.version)
        raise ArgumentError, "version is on the kill list and can never be released"
      end
      # A quarantined placeholder (only rejected history besides this version)
      # reactivates when its correction releases; anything else must be active.
      placeholder_correction = version.plugin.quarantined? &&
        version.plugin.versions.where.not(state: :rejected).where.not(id: version.id).none?
      unless version.plugin.active? || placeholder_correction
        raise ArgumentError, "cannot release into a #{version.plugin.state} plugin"
      end
      # Suspension or membership loss between submit and release must stop the
      # release — the hold window exists precisely for this.
      raise ArgumentError, "publisher is suspended" if version.plugin.publisher.suspended?
      if (submitter = version.user) && !submitter.system?
        raise ArgumentError, "submitter is suspended" if submitter.suspended_at.present?
        unless submitter.member_of?(version.plugin.publisher)
          raise ArgumentError, "submitter is no longer a member of #{version.plugin.publisher.name}"
        end
        # Same bar as publishing: losing the second factor or a fresh sensitive
        # change pauses releases too, not just new submissions
        raise ArgumentError, "submitter can no longer publish (second factor or cooldown)" unless submitter.can_publish?
      end

      bytes = version.tarball.download
      raise "tarball checksum mismatch at release" unless Digest::SHA256.hexdigest(bytes) == version.sha256

      ApplicationRecord.transaction do
        version.plugin.update!(state: :active) if placeholder_correction
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
    private_class_method :locked_call
  end
end
