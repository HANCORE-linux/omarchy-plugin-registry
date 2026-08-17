module Admin
  class ReportsController < BaseController
    def resolve
      report = Report.find(params[:id])
      hidden = params[:hide] == "1" && report.reportable.is_a?(Comment)
      report.reportable.hide!(actor: Current.user) if hidden
      report.resolve!(Current.user)
      AuditEvent.record!(actor: Current.user, action: hidden ? "report.resolve_hide" : "report.dismiss",
        subject: report, metadata: { reportable: "#{report.reportable_type}##{report.reportable_id}", reason: report.reason })
      redirect_to admin_root_path, notice: "Report resolved."
    end
  end
end
