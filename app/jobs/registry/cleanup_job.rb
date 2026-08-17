module Registry
  # Recurring housekeeping: dead device-flow rows and stale login codes.
  class CleanupJob < ApplicationJob
    queue_as :default

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

    # Rejected uploads keep their metadata row forever (the version number is
    # burned) but not their bytes — retained tarballs would otherwise be an
    # unbounded storage sink. Quarantined bytes stay (under investigation);
    # published/yanked bytes stay (reproducibility).
    def purge_rejected_tarballs
      PluginVersion.rejected.where(updated_at: ...30.days.ago).find_each do |version|
        version.tarball.purge if version.tarball.attached?
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
