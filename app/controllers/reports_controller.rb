class ReportsController < ApplicationController
  rate_limit to: 10, within: 1.hour, only: :create,
    with: -> { redirect_back fallback_location: root_path, alert: "Slow down." }

  REPORTABLE = { "Comment" => Comment, "Plugin" => Plugin }.freeze

  def create
    klass = REPORTABLE[params[:reportable_type]] or return head :bad_request
    reportable = klass.find(params[:reportable_id])
    Report.create!(user: Current.user, reportable:, reason: params[:reason].presence || "unspecified")
    redirect_back fallback_location: root_path, notice: "Reported — an admin will take a look."
  end
end
