module Admin
  class ReportsController < BaseController
    def resolve
      report = Report.find(params[:id])
      if params[:hide] == "1" && report.reportable.is_a?(Comment)
        report.reportable.hide!(actor: Current.user)
      end
      report.resolve!(Current.user)
      redirect_to admin_root_path, notice: "Report resolved."
    end
  end
end
