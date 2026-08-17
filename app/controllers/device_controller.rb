# Browser side of the CLI device flow: enter the code, pick the scope, approve.
class DeviceController < ApplicationController
  def show
    @user_code = params[:code]
    @authorization = DeviceAuthorization.find_by_user_code(@user_code) if @user_code.present?
    if @user_code.present? && @authorization.nil?
      flash.now[:alert] = "That code isn't valid — it may have expired. Re-run the command and try again."
    end
  end

  def approve
    authorization = DeviceAuthorization.find_by_user_code(params[:code])
    return redirect_to device_path, alert: "That code expired — re-run the command." if authorization.nil?
    unless Current.user.second_factor?
      return redirect_to settings_two_factor_path, alert: "Add a passkey or enable two-factor authentication before authorizing publishes."
    end

    if params[:decision] == "deny"
      authorization.deny!(user: Current.user)
      return redirect_to dashboard_path, notice: "Denied. The CLI has been told no."
    end

    publisher = Current.user.publishers.find_by(name: params[:publisher_name])
    plugin_name = params[:plugin_name].to_s.downcase.strip
    if publisher.nil? || !plugin_name.match?(NameRules::NAME_FORMAT)
      return redirect_to device_path(code: params[:code]), alert: "Pick a namespace and a valid plugin name."
    end

    authorization.approve!(user: Current.user, publisher:, plugin_name:)
    AuditEvent.record!(actor: Current.user, action: "device.approve", subject: authorization,
      metadata: { scope: "#{publisher.name}/#{plugin_name}" })
    redirect_to dashboard_path, notice: "Approved — your terminal has its token. It expires in 7 days."
  end
end
