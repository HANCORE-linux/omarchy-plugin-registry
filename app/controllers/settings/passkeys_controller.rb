module Settings
  class PasskeysController < ApplicationController
    before_action :require_recent_second_factor, only: :destroy
    before_action :require_step_up_if_second_factor_enrolled, only: %i[options create]

    # POST /settings/passkeys/options — creation options for the browser ceremony
    def options
      user = Current.user
      user.update!(webauthn_id: WebAuthn.generate_user_id) if user.webauthn_id.blank?

      # UV required at registration too — a presence-only credential must never
      # become a factor that sign-in and step-up would then have to honor.
      creation_options = WebAuthn::Credential.options_for_create(
        user: { id: user.webauthn_id, name: user.email_address, display_name: user.name.to_s },
        exclude: user.passkeys.pluck(:external_id),
        # resident_key required: username-less sign-in supplies no credential
        # allowlist, so non-discoverable credentials could never sign in
        authenticator_selection: { resident_key: "required", user_verification: "required" }
      )
      session[:webauthn_challenge] = creation_options.challenge
      render json: creation_options
    end

    def create
      credential = WebAuthn::Credential.from_create(JSON.parse(params.require(:credential)))
      credential.verify(session.delete(:webauthn_challenge), user_verification: true)

      Current.user.passkeys.create!(
        external_id: credential.id,
        public_key: credential.public_key,
        sign_count: credential.sign_count,
        nickname: params[:nickname].presence || "Passkey"
      )
      AuditEvent.record!(actor: Current.user, action: "passkey.register", subject: Current.user)
      # Only FIRST enrollment bootstraps verification; adding a factor later
      # required step-up already and must not extend it via registration.
      if Current.user.passkeys.count == 1 && !Current.user.otp_enabled?
        mark_second_factor_verified!
        apply_first_factor_cooldown(Current.user)
      end
      # Recovery-based enrollment closes the recovery window and applies the
      # full sensitive-change cooldown — a 72-hour hijack can't mint anything
      # for another cooldown period after it lands
      if Current.user.recovery_requested_at
        Current.user.update!(recovery_requested_at: nil, sensitive_change_at: Time.current)
      end
      render json: { ok: true }
    rescue WebAuthn::Error, JSON::ParserError => e
      render json: { error: "Passkey registration failed: #{e.message}" }, status: :unprocessable_entity
    end

    def destroy
      passkey = Current.user.passkeys.find(params[:id])
      # Admins and publisher members may never drop to zero factors — an
      # email-only takeover could otherwise remove-then-re-enroll its own
      # factor and inherit the account's powers.
      would_have_factor = Current.user.otp_enabled? || Current.user.passkeys.where.not(id: passkey.id).exists?
      if !would_have_factor && (Current.user.admin? || Current.user.memberships.exists?) && !Current.user.recovery_ready?
        return redirect_to settings_two_factor_path,
          alert: "Add a replacement factor before removing your last one."
      end

      passkey.destroy!
      # Losing a second factor is a sensitive change — publish cooldown applies
      Current.user.update!(sensitive_change_at: Time.current)
      redirect_to settings_two_factor_path, notice: "Passkey removed."
    end
  end
end
