# First sign-in lands here: pick a display name and claim a personal namespace.
class OnboardingController < ApplicationController
  # Namespaces are burned forever — throttle claim attempts per ACCOUNT (an
  # office NAT full of new users must not share one budget)
  rate_limit to: 5, within: 1.day, only: :create,
    by: -> { Current.user&.id || request.remote_ip },
    with: -> { redirect_to onboarding_path, alert: "Too many attempts today." }

  def show
    redirect_to dashboard_path if Current.user.onboarded?
  end

  # One-shot: a user with a personal namespace only fills in their name — no
  # second handle can ever be claimed through onboarding (namespaces are
  # first-claim and burned, so repeat POSTs would be a squatting vector).
  def create
    user = Current.user
    return redirect_to dashboard_path if user.onboarded?

    display_name = params[:name].to_s.strip.presence || user.email_address.split("@").first
    handle = params[:handle].to_s.downcase.strip
    publisher = Publisher.new(name: handle, kind: :personal)

    # The one-namespace check runs under the user row lock — parallel repeat
    # POSTs serialize, and only one can ever claim a personal namespace
    already_claimed = false
    ApplicationRecord.transaction do
      user.lock!
      user.update!(name: display_name)
      if user.personal_publisher.present?
        already_claimed = true
      else
        publisher.save!
        Membership.create!(publisher:, user:, role: :owner, founding: true)
      end
    end
    return redirect_to dashboard_path, notice: "Welcome back." if already_claimed
    AuditEvent.record!(actor: user, action: "publisher.claim", subject: publisher, public: true,
      metadata: { name: publisher.name })
    redirect_to settings_two_factor_path, notice: "Namespace #{handle} is yours. Set up two-factor auth to publish."
  rescue ActiveRecord::RecordInvalid
    @handle_errors = publisher.errors.full_messages
    render :show, status: :unprocessable_entity
  end
end
