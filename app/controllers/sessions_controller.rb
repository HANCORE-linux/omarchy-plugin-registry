# Passwordless sign-in, the Cortex/Herald flow: email -> one-time code ->
# session. Unknown emails get an account created on first sign-in and finish
# onboarding (name + namespace) afterwards.
class SessionsController < ApplicationController
  include DevLoginCode

  allow_unauthenticated_access except: :destroy
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_url, alert: "Try again later." }
  # A 6-digit code must not be guessable: throttle redemption attempts per IP
  # (per-code attempt lockout lives in User#redeem_login_code).
  rate_limit to: 10, within: 15.minutes, only: :authenticate,
    with: -> { redirect_to new_session_url, alert: "Too many attempts — request a fresh code in a few minutes." }

  def new
    redirect_to dashboard_path, notice: "You are already signed in." if authenticated?
  end

  # Step 1: email in, code out
  def create
    email = params[:email_address].to_s.strip.downcase
    unless email.match?(URI::MailTo::EMAIL_REGEXP)
      flash.now[:alert] = "Enter a valid email address."
      return render :new, status: :unprocessable_entity
    end

    user = User.find_or_create_by!(email_address: email)
    expose_login_code_in_dev user.send_login_code

    redirect_to verify_session_path(email_address: email), notice: "Check your email for a sign-in code."
  end

  # Step 2: code form
  def verify
    @email_address = params[:email_address]
    redirect_to new_session_path, alert: "Enter your email first." if @email_address.blank?
  end

  # Step 3: redeem code, start session
  def authenticate
    email = params[:email_address].to_s.strip.downcase
    user = User.find_by(email_address: email)

    if user&.redeem_login_code(params[:code])
      start_new_session_for user
      redirect_to user.onboarded? ? after_authentication_url : onboarding_path
    else
      flash.now[:alert] = "Invalid or expired code — try again."
      @email_address = email
      render :verify, status: :unprocessable_entity
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, notice: "Signed out."
  end
end
