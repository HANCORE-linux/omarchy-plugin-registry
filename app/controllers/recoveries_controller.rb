# Lost-factor recovery: starts the 72-hour countdown after which factor
# management reopens without step-up. Announced by email immediately; any
# successful step-up cancels it.
class RecoveriesController < ApplicationController
  rate_limit to: 3, within: 1.day, only: :create,
    with: -> { redirect_to step_up_path, alert: "Recovery was already requested recently." }
  # Cancelling is itself factor-proof: an email-only attacker session must not
  # be able to repeatedly obstruct the owner's legitimate recovery
  before_action :require_recent_second_factor, only: :destroy

  def create
    user = Current.user
    unless user.second_factor?
      return redirect_to settings_two_factor_path, alert: "No factor to recover — just enroll one."
    end

    if user.recovery_requested_at.nil?
      user.update!(recovery_requested_at: Time.current)
      RecoveryMailer.recovery_started(user).deliver_later
      AuditEvent.record!(actor: user, action: "account.recovery_requested", subject: user)
    end
    redirect_to step_up_path,
      notice: "Recovery started. In #{User::RECOVERY_DELAY.inspect} you can enroll a replacement factor. If this wasn't you, complete a step-up to cancel it."
  end

  def destroy
    Current.user.update!(recovery_requested_at: nil)
    AuditEvent.record!(actor: Current.user, action: "account.recovery_cancelled", subject: Current.user)
    redirect_to dashboard_path, notice: "Recovery cancelled."
  end
end
