# First sign-in lands here: pick a display name and claim a personal namespace.
class OnboardingController < ApplicationController
  def show
    redirect_to dashboard_path if Current.user.onboarded?
  end

  def create
    user = Current.user
    handle = params[:handle].to_s.downcase.strip
    publisher = Publisher.new(name: handle, kind: :personal)

    ApplicationRecord.transaction do
      user.update!(name: params[:name].to_s.strip.presence || user.email_address.split("@").first)
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
