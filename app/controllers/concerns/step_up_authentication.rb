# Enrollment is not verification: minting credentials, authorizing devices,
# registering CI publishers, and removing second factors all require that THIS
# session proved a second factor recently — not merely that one is on file.
module StepUpAuthentication
  extend ActiveSupport::Concern

  FRESHNESS = 30.minutes

  private

  # For second-factor MANAGEMENT (adding/removing factors): open on first
  # enrollment, gated once any factor exists — email compromise must not be
  # able to add an attacker-controlled factor next to a real one.
  def require_step_up_if_second_factor_enrolled
    require_recent_second_factor if Current.user.second_factor?
  end

  # The sensitive-change cooldown gates EVERY credential-shaped action, not
  # just publishes — a just-enrolled factor must not immediately mint tokens,
  # approve devices, or register CI publishers.
  def require_no_sensitive_cooldown
    if Current.user.in_publish_cooldown?
      redirect_back fallback_location: dashboard_path,
        alert: "This account had a recent security-sensitive change — credential actions resume after the cooldown."
    end
  end

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

  # First-factor enrollment on an ESTABLISHED account is what an email-only
  # takeover looks like — apply the sensitive-change cooldown so the hijacker
  # can't immediately mint credentials. Brand-new accounts enroll freely.
  def apply_first_factor_cooldown(user)
    user.update!(sensitive_change_at: Time.current) if user.created_at < 1.day.ago
  end
end
