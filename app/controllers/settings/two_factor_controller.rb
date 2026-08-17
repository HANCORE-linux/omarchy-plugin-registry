module Settings
  class TwoFactorController < ApplicationController
    def show
      @user = Current.user
      @user.provision_otp! if @user.otp_secret.blank? && !@user.otp_enabled?
      if !@user.otp_enabled?
        @qr_svg = RQRCode::QRCode.new(@user.otp_provisioning_uri).as_svg(module_size: 4, use_path: true)
      end
    end

    # Confirm enrollment with a code from the authenticator
    def update
      @user = Current.user
      if @user.enable_otp!(params[:code])
        redirect_to dashboard_path, notice: "Two-factor authentication enabled. Save your backup codes from this page."
      else
        redirect_to settings_two_factor_path, alert: "That code didn't match — try again."
      end
    end
  end
end
