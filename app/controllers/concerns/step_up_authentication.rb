# Enrollment is not verification: minting credentials, authorizing devices,
# registering CI publishers, and removing second factors all require that THIS
# session proved a second factor recently — not merely that one is on file.
module StepUpAuthentication
  extend ActiveSupport::Concern

  FRESHNESS = 30.minutes

  private

  def require_recent_second_factor
    user = Current.user
    unless user.second_factor?
      return redirect_to settings_two_factor_path,
        alert: "Add a passkey or enable two-factor authentication first."
    end
    return if second_factor_fresh?

    session[:after_step_up] = (request.get? || request.head?) ? request.fullpath : (request.referer.presence || dashboard_path)
    redirect_to step_up_path, alert: "Confirm your second factor to continue."
  end

  def second_factor_fresh?
    Current.session&.second_factor_verified_at&.after?(FRESHNESS.ago) || false
  end

  def mark_second_factor_verified!
    Current.session&.update!(second_factor_verified_at: Time.current)
  end
end
