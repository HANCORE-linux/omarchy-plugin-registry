# Passwordless × unphishable: sign in with a passkey directly, no email code.
class PasskeySessionsController < ApplicationController
  allow_unauthenticated_access

  def options
    get_options = WebAuthn::Credential.options_for_get(user_verification: "preferred")
    session[:webauthn_auth_challenge] = get_options.challenge
    render json: get_options
  end

  def create
    credential = WebAuthn::Credential.from_get(JSON.parse(params.require(:credential)))
    passkey = Passkey.find_by(external_id: credential.id)
    raise WebAuthn::Error, "unknown credential" if passkey.nil?

    credential.verify(
      session.delete(:webauthn_auth_challenge),
      public_key: passkey.public_key,
      sign_count: passkey.sign_count
    )
    passkey.update!(sign_count: credential.sign_count, last_used_at: Time.current)
    start_new_session_for passkey.user
    # A passkey sign-in IS a second-factor proof for this session
    mark_second_factor_verified!
    render json: { redirect: passkey.user.onboarded? ? after_authentication_url : onboarding_path }
  rescue WebAuthn::Error, JSON::ParserError => e
    render json: { error: "Passkey sign-in failed: #{e.message}" }, status: :unauthorized
  end
end
