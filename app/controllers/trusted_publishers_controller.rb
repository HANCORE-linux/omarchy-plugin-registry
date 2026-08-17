class TrustedPublishersController < ApplicationController
  before_action :require_recent_second_factor

  def create
    publisher = Current.user.publishers.find_by!(name: params[:publisher_name])
    return redirect_to dashboard_path, alert: "Only namespace owners can register trusted publishers." unless Current.user.owner_of?(publisher)

    trusted = TrustedPublisher.new(
      publisher:,
      plugin_name: params[:plugin_name].to_s.downcase.strip,
      repository: params[:repository].to_s.strip,
      workflow: params[:workflow].to_s.strip,
      environment: params[:environment].presence || "release",
      created_by: Current.user
    )
    if trusted.save
      AuditEvent.record!(actor: Current.user, action: "trusted_publisher.create", subject: trusted,
        metadata: { scope: "#{publisher.name}/#{trusted.plugin_name}", repository: trusted.repository })
      redirect_to dashboard_path, notice: "Trusted publishing enabled: #{trusted.repository} → #{publisher.name}/#{trusted.plugin_name}."
    else
      redirect_to dashboard_path, alert: trusted.errors.full_messages.join("; ")
    end
  end

  def destroy
    trusted = TrustedPublisher.find(params[:id])
    return head :forbidden unless Current.user.owner_of?(trusted.publisher)
    trusted.destroy!
    AuditEvent.record!(actor: Current.user, action: "trusted_publisher.remove", subject: trusted.publisher,
      metadata: { scope: "#{trusted.publisher.name}/#{trusted.plugin_name}" })
    redirect_to dashboard_path, notice: "Trusted publisher removed."
  end
end
