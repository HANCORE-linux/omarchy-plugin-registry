# The step-up gate: confirm a TOTP code or a passkey assertion for the current
# session before sensitive actions proceed.
class StepUpController < ApplicationController
  rate_limit to: 10, within: 15.minutes, only: :create,
    with: -> { redirect_to step_up_path, alert: "Too many attempts — wait a few minutes." }

  def show
  end

  # TOTP path. Failures burn a per-SESSION budget (IP rotation doesn't reset
  # it); exhausting it kills the session outright.
  MAX_SESSION_FAILURES = 5

  def create
    if Current.user.verify_otp(params[:code])
      Current.session.update!(step_up_failures: 0)
      # A successful step-up proves the factor isn't lost — cancel any
      # recovery countdown (the real owner wins)
      Current.user.update!(recovery_requested_at: nil) if Current.user.recovery_requested_at
      mark_second_factor_verified!
      redirect_to session.delete(:after_step_up) || dashboard_path, notice: "Verified."
    else
      Current.session.increment!(:step_up_failures)
      if Current.session.step_up_failures >= MAX_SESSION_FAILURES
        terminate_session
        redirect_to new_session_path, alert: "Too many failed attempts — sign in again."
      else
        redirect_to step_up_path, alert: "That code didn't match."
      end
    end
  end

  # Passkey path: assertion restricted to the signed-in user's credentials.
  # UV required — step-up is exactly the moment presence-only must not count.
  def passkey_options
    get_options = WebAuthn::Credential.options_for_get(
      allow: Current.user.passkeys.pluck(:external_id),
      user_verification: "required"
    )
    session[:webauthn_step_up_challenge] = get_options.challenge
    render json: get_options
  end

  def passkey_verify
    credential = WebAuthn::Credential.from_get(JSON.parse(params.require(:credential)))
    passkey = Current.user.passkeys.find_by(external_id: credential.id)
    raise WebAuthn::Error, "unknown credential" if passkey.nil?

    credential.verify(
      session.delete(:webauthn_step_up_challenge),
      public_key: passkey.public_key,
      sign_count: passkey.sign_count,
      user_verification: true
    )
    passkey.update!(sign_count: credential.sign_count, last_used_at: Time.current)
    mark_second_factor_verified!
    render json: { redirect: session.delete(:after_step_up) || dashboard_path }
  rescue WebAuthn::Error, JSON::ParserError => e
    render json: { error: "Passkey verification failed: #{e.message}" }, status: :unauthorized
  end
end
