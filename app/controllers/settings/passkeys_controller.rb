module Settings
  class PasskeysController < ApplicationController
    before_action :require_recent_second_factor, only: :destroy
    before_action :require_step_up_if_second_factor_enrolled, only: %i[options create]

    # POST /settings/passkeys/options — creation options for the browser ceremony
    def options
      user = Current.user
      user.update!(webauthn_id: WebAuthn.generate_user_id) if user.webauthn_id.blank?

      creation_options = WebAuthn::Credential.options_for_create(
        user: { id: user.webauthn_id, name: user.email_address, display_name: user.name.to_s },
        exclude: user.passkeys.pluck(:external_id),
        authenticator_selection: { resident_key: "preferred", user_verification: "preferred" }
      )
      session[:webauthn_challenge] = creation_options.challenge
      render json: creation_options
    end

    def create
      credential = WebAuthn::Credential.from_create(JSON.parse(params.require(:credential)))
      credential.verify(session.delete(:webauthn_challenge))

      Current.user.passkeys.create!(
        external_id: credential.id,
        public_key: credential.public_key,
        sign_count: credential.sign_count,
        nickname: params[:nickname].presence || "Passkey"
      )
      AuditEvent.record!(actor: Current.user, action: "passkey.register", subject: Current.user)
      # Only FIRST enrollment bootstraps verification; adding a factor later
      # required step-up already and must not extend it via registration.
      mark_second_factor_verified! if Current.user.passkeys.count == 1 && !Current.user.otp_enabled?
      render json: { ok: true }
    rescue WebAuthn::Error, JSON::ParserError => e
      render json: { error: "Passkey registration failed: #{e.message}" }, status: :unprocessable_entity
    end

    def destroy
      Current.user.passkeys.find(params[:id]).destroy!
      # Losing a second factor is a sensitive change — publish cooldown applies
      Current.user.update!(sensitive_change_at: Time.current)
      redirect_to settings_two_factor_path, notice: "Passkey removed."
    end
  end
end
