module Registry
  # Recurring housekeeping: dead device-flow rows and stale login codes.
  class CleanupJob < ApplicationJob
    queue_as :critical

    def perform
      DeviceAuthorization.where(expires_at: ...1.day.ago).delete_all
      LoginCode.where(created_at: ...1.day.ago).delete_all
      ApiToken.where(expires_at: ...30.days.ago).delete_all
      Session.expired.delete_all
      purge_rejected_tarballs
      resume_stuck_pipeline_work
      Plugin.find_each(&:flush_cached_views!) if Rails.env.production?
    end

    private

    # Storage retention is bounded for everything that never shipped:
    # - rejected uploads lose their bytes after 30 days (rows stay burned)
    # - NEVER-published quarantined uploads that nobody touched for 90 days
    #   expire to rejected and lose their bytes — the admin queue is not an
    #   indefinite free storage locker
    # Published/yanked bytes stay (reproducibility); once-published quarantined
    # bytes stay (under investigation, were public).
    def purge_rejected_tarballs
      PluginVersion.rejected.where(updated_at: ...30.days.ago).find_each do |version|
        version.tarball.purge if version.tarball.attached?
      end

      PluginVersion.quarantined.where(published_at: nil).where(updated_at: ...90.days.ago).find_each do |version|
        version.update!(state: :rejected, review_notes: "#{version.review_notes} [expired unreviewed after 90 days]".strip)
        version.tarball.purge if version.tarball.attached?
        AuditEvent.record!(action: "version.quarantine_expired", subject: version, public: true,
          metadata: { plugin: version.plugin.full_name, version: version.version })
      end
    end

    # A lost enqueue must never strand a version: re-drive processing versions
    # through review and overdue held versions through release.
    def resume_stuck_pipeline_work
      PluginVersion.processing.where(created_at: ...10.minutes.ago).find_each do |version|
        ReviewJob.perform_later(version)
      end
      PluginVersion.held.where(hold_until: ...5.minutes.ago).find_each do |version|
        ReleaseJob.perform_later(version)
      end
    end
  end
end
