module Registry
  # Recurring housekeeping: dead device-flow rows and stale login codes.
  class CleanupJob < ApplicationJob
    queue_as :default

    def perform
      DeviceAuthorization.where(expires_at: ...1.day.ago).delete_all
      LoginCode.where(created_at: ...1.day.ago).delete_all
      ApiToken.where(expires_at: ...30.days.ago).delete_all
      Session.expired.delete_all
      resume_stuck_pipeline_work
    end

    private

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
