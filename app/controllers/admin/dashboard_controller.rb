module Admin
  # The human-escalation queue: quarantined/held versions, plus recent activity.
  class DashboardController < BaseController
    def show
      @queue = PluginVersion.where(state: [ :quarantined, :held, :processing ])
        .includes(plugin: :publisher).order(:created_at)
      @recent_versions = PluginVersion.includes(plugin: :publisher).order(created_at: :desc).limit(20)
      @recent_events = AuditEvent.order(created_at: :desc).includes(:user).limit(30)
      @revocations = Revocation.includes(plugin: :publisher).order(created_at: :desc).limit(10)
      @reports = Report.open.includes(:user, :reportable).order(:created_at)
    end
  end
end
