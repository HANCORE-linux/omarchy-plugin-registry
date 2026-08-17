# First sign-in lands here: pick a display name and claim a personal namespace.
class OnboardingController < ApplicationController
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
    if user.personal_publisher.present?
      user.update!(name: display_name)
      return redirect_to dashboard_path, notice: "Welcome back."
    end

    handle = params[:handle].to_s.downcase.strip
    publisher = Publisher.new(name: handle, kind: :personal)

    ApplicationRecord.transaction do
      user.update!(name: display_name)
      publisher.save!
      Membership.create!(publisher:, user:, role: :owner)
    end
    AuditEvent.record!(actor: user, action: "publisher.claim", subject: publisher, public: true,
      metadata: { name: publisher.name })
    redirect_to settings_two_factor_path, notice: "Namespace #{handle} is yours. Set up two-factor auth to publish."
  rescue ActiveRecord::RecordInvalid
    @handle_errors = publisher.errors.full_messages
    render :show, status: :unprocessable_entity
  end
end
