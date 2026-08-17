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

  # Step 1: email in, code out. The email travels in the server session, never
  # a query string — URLs land in browser history and proxy/CDN logs.
  def create
    email = params[:email_address].to_s.strip.downcase
    unless email.match?(URI::MailTo::EMAIL_REGEXP)
      flash.now[:alert] = "Enter a valid email address."
      return render :new, status: :unprocessable_entity
    end

    user = User.find_or_create_by!(email_address: email)
    expose_login_code_in_dev user.send_login_code
    session[:pending_email] = email

    redirect_to verify_session_path, notice: "Check your email for a sign-in code."
  end

  # Step 2: code form
  def verify
    @email_address = session[:pending_email]
    redirect_to new_session_path, alert: "Enter your email first." if @email_address.blank?
  end

  # Step 3: redeem code, start session
  def authenticate
    email = session[:pending_email].to_s
    user = User.find_by(email_address: email)

    if user&.suspended_at&.present?
      redirect_to new_session_path, alert: "This account is suspended. Contact registry@omarchy.org."
    elsif user&.redeem_login_code(params[:code])
      session.delete(:pending_email)
      start_new_session_for user
      # A saved destination (e.g. a seeded-namespace claim link) wins over
      # onboarding — forcing a claimant through handle-claiming first would
      # burn an unrelated permanent namespace.
      if session[:return_to_after_authenticating].present? || user.onboarded?
        redirect_to after_authentication_url
      else
        redirect_to onboarding_path
      end
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
