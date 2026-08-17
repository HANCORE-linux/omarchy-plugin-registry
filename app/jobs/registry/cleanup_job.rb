module Registry
  # Recurring housekeeping: dead device-flow rows and stale login codes.
  class CleanupJob < ApplicationJob
    queue_as :default

    def perform
      DeviceAuthorization.where(expires_at: ...1.day.ago).delete_all
      LoginCode.where(created_at: ...1.day.ago).delete_all
      ApiToken.where(expires_at: ...30.days.ago).delete_all
      Session.expired.delete_all
    end
  end
end
