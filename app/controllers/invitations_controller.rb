# Accepting or declining an org invitation — only the invitee can act on it.
class InvitationsController < ApplicationController
  def accept
    invitation = Current.user.memberships.pending.find(params[:id])
    invitation.accept!
    AuditEvent.record!(actor: Current.user, action: "org.invite_accept", subject: invitation.publisher,
      metadata: { member: Current.user.email_address })
    redirect_to dashboard_path, notice: "You're now a #{invitation.role} of #{invitation.publisher.name}. The publish cooldown applies before you can publish there."
  end

  def decline
    invitation = Current.user.memberships.pending.find(params[:id])
    publisher = invitation.publisher
    invitation.destroy!
    redirect_to dashboard_path, notice: "Invitation from #{publisher.name} declined."
  end
end
