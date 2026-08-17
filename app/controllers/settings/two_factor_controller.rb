module Settings
  class TwoFactorController < ApplicationController
    # Provisioning (show displays the new secret) and confirming TOTP next to
    # an existing factor both require step-up; first enrollment stays open.
    before_action :require_step_up_if_second_factor_enrolled
    # TOTP secrets and one-time backup codes must never land in a shared cache
    after_action { response.headers["Cache-Control"] = "no-store" }

    # The provisional secret lives ONLY in this browser's encrypted session
    # and expires — it reaches the account solely when THIS enrollment
    # confirms it, so nothing recordable-in-advance ever becomes the seed.
    PROVISIONAL_TTL = 30.minutes

    def show
      @user = Current.user
      if !@user.otp_enabled?
        @provisional_secret = provisional_otp_secret!
        @qr_svg = RQRCode::QRCode.new(@user.otp_provisioning_uri(@provisional_secret))
          .as_svg(module_size: 4, use_path: true)
      end
      # Backup codes are shown exactly once, right after enrollment
      @backup_codes = flash[:backup_codes]
    end

    # Confirm enrollment with a code from the authenticator
    def update
      @user = Current.user
      # The whole enrollment decision runs under the user row lock: the
      # pre-enrollment factor state, the enable, and the first-factor cooldown
      # commit atomically — a concurrent passkey enrollment can't make both
      # paths see "another factor exists" and both skip the cooldown.
      secret = pending_otp_secret
      if secret.blank?
        return redirect_to settings_two_factor_path,
          alert: "Enrollment expired — scan the fresh code and try again."
      end
      codes = was_first_factor = was_recovery = nil
      @user.with_lock do
        # Captured BEFORE verification marks — mark_second_factor_verified!
        # clears the recovery flag, and the cooldown must not miss that
        was_recovery = @user.recovery_requested_at.present?
        was_first_factor = !@user.otp_enabled? && !@user.passkeys.exists?
        codes = @user.enable_otp!(params[:code], secret:)
        if codes
          apply_first_factor_cooldown(@user) if was_first_factor
          @user.update!(recovery_requested_at: nil, sensitive_change_at: Time.current) if was_recovery
        end
      end
      if codes
        session.delete(:pending_otp)
        mark_second_factor_verified!
        flash[:backup_codes] = codes
        redirect_to settings_two_factor_path, notice: "Two-factor authentication enabled. Save your backup codes now — this is the only time they're shown."
      else
        redirect_to settings_two_factor_path, alert: "That code didn't match — try again."
      end
    end

    # Rotation/removal lifecycle: a compromised seed must be revocable. Gated
    # by step-up; the same no-zero-factors rule as passkey removal applies.
    def destroy
      user = Current.user
      unless user.otp_enabled?
        return redirect_to settings_two_factor_path, alert: "TOTP is not enabled."
      end
      # A matured recovery may drop to zero factors — that IS the recovery
      # path for a TOTP-only publisher who lost their authenticator
      if !user.passkeys.exists? && (user.admin? || user.memberships.accepted.exists?) && !user.recovery_ready?
        return redirect_to settings_two_factor_path, alert: "Add a passkey before removing TOTP — you can't drop to zero factors."
      end

      user.update!(otp_secret: nil, otp_enabled_at: nil, otp_backup_codes: nil,
        sensitive_change_at: Time.current)
      AuditEvent.record!(actor: user, action: "totp.disable", subject: user)
      redirect_to settings_two_factor_path, notice: "TOTP disabled. Re-enroll any time (a fresh secret will be generated); the security cooldown applies."
    end

    private

    # Fresh (or still-fresh) provisional secret, session-bound and expiring.
    # Regenerating on expiry also invalidates any prior pending enrollment.
    def provisional_otp_secret!
      pending_otp_secret || begin
        secret = ROTP::Base32.random
        session[:pending_otp] = { "secret" => secret, "at" => Time.current.to_i, "user_id" => Current.user.id }
        secret
      end
    end

    def pending_otp_secret
      pending = session[:pending_otp]
      return nil if pending.blank? || pending["at"].to_i < PROVISIONAL_TTL.ago.to_i
      # Bound to the account that provisioned it — never portable across users
      return nil unless pending["user_id"] == Current.user.id
      pending["secret"]
    end
  end
end
