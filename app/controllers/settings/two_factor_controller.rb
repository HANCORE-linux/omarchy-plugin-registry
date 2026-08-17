module Settings
  class TwoFactorController < ApplicationController
    # Provisioning (show displays the new secret) and confirming TOTP next to
    # an existing factor both require step-up; first enrollment stays open.
    before_action :require_step_up_if_second_factor_enrolled
    # TOTP secrets and one-time backup codes must never land in a shared cache
    after_action { response.headers["Cache-Control"] = "no-store" }

    def show
      @user = Current.user
      @user.provision_otp! if @user.otp_secret.blank? && !@user.otp_enabled?
      if !@user.otp_enabled?
        @qr_svg = RQRCode::QRCode.new(@user.otp_provisioning_uri).as_svg(module_size: 4, use_path: true)
      end
      # Backup codes are shown exactly once, right after enrollment
      @backup_codes = flash[:backup_codes]
    end

    # Confirm enrollment with a code from the authenticator
    def update
      @user = Current.user
      if (codes = @user.enable_otp!(params[:code]))
        mark_second_factor_verified!
        apply_first_factor_cooldown(@user) unless @user.passkeys.exists?
        @user.update!(recovery_requested_at: nil, sensitive_change_at: Time.current) if @user.recovery_requested_at
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
      if !user.passkeys.exists? && (user.admin? || user.memberships.exists?) && !user.recovery_ready?
        return redirect_to settings_two_factor_path, alert: "Add a passkey before removing TOTP — you can't drop to zero factors."
      end

      user.update!(otp_secret: nil, otp_enabled_at: nil, otp_backup_codes: nil,
        sensitive_change_at: Time.current)
      AuditEvent.record!(actor: user, action: "totp.disable", subject: user)
      redirect_to settings_two_factor_path, notice: "TOTP disabled. Re-enroll any time (a fresh secret will be generated); the security cooldown applies."
    end
  end
end
