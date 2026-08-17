module Settings
  class TwoFactorController < ApplicationController
    # Provisioning (show displays the new secret) and confirming TOTP next to
    # an existing factor both require step-up; first enrollment stays open.
    before_action :require_step_up_if_second_factor_enrolled

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
      if @user.enable_otp!(params[:code])
        mark_second_factor_verified!
        flash[:backup_codes] = @user.otp_backup_codes
        redirect_to settings_two_factor_path, notice: "Two-factor authentication enabled. Save your backup codes now — this is the only time they're shown."
      else
        redirect_to settings_two_factor_path, alert: "That code didn't match — try again."
      end
    end
  end
end
