class OrgsController < ApplicationController
  before_action :require_recent_second_factor, only: %i[invite_member remove_member]
  before_action :require_no_sensitive_cooldown, only: :invite_member
  # Namespaces are first-claim and burned forever. The durable control is a
  # per-ACCOUNT ledger (founding org memberships), not a rotatable IP limit.
  MAX_ORGS_PER_WEEK = 3

  def new
    @publisher = Publisher.new(kind: :org)
  end

  # Quota check and creation are ONE atomic unit under the user row lock —
  # parallel requests serialize, and the audit ledger (which member removal
  # can't erase) commits with the namespace or not at all.
  def create
    @publisher = Publisher.new(name: params.dig(:publisher, :name).to_s.downcase.strip,
      display_name: params.dig(:publisher, :display_name), kind: :org)
    quota_hit = false
    ApplicationRecord.transaction do
      Current.user.lock!
      recent = AuditEvent.where(user: Current.user, action: "org.create", created_at: 7.days.ago..).count
      if recent >= MAX_ORGS_PER_WEEK
        quota_hit = true
        raise ActiveRecord::Rollback
      end
      unless @publisher.save
        raise ActiveRecord::Rollback
      end
      Membership.create!(publisher: @publisher, user: Current.user, role: :owner, founding: true)
      AuditEvent.record!(actor: Current.user, action: "org.create", subject: @publisher,
        public: true, metadata: { name: @publisher.name })
    end
    if quota_hit
      redirect_to dashboard_path, alert: "Org creation is limited to #{MAX_ORGS_PER_WEEK} per week per account."
    elsif @publisher.persisted?
      redirect_to dashboard_path, notice: "Org #{@publisher.name} created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Invitation-based: no membership exists without the invitee's consent, and
  # the response never reveals whether the email has an account.
  def invite_member
    publisher = Publisher.org.find(params[:id])
    return head :forbidden unless Current.user.owner_of?(publisher)

    user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)
    if user && !publisher.memberships.exists?(user:)
      Membership.create!(publisher:, user:, role: params[:role] == "owner" ? :owner : :publisher, accepted_at: nil)
      AuditEvent.record!(actor: Current.user, action: "org.member_invite", subject: publisher,
        metadata: { member: user.email_address })
    end
    redirect_to dashboard_path, notice: "If that account exists, an invitation is waiting on their dashboard."
  end

  # A departed or compromised member must be removable — and their scoped
  # tokens die with the membership.
  def remove_member
    publisher = Publisher.org.find(params[:id])
    return head :forbidden unless Current.user.owner_of?(publisher)

    membership = publisher.memberships.find(params[:membership_id])
    # Only ACCEPTED owners count — a pending invitation is a maybe, and the
    # invitee declining must never leave the namespace ownerless
    if membership.role_owner? && !membership.pending? && publisher.memberships.owner.accepted.count == 1
      return redirect_to dashboard_path, alert: "An org needs at least one accepted owner."
    end

    ApplicationRecord.transaction do
      membership.destroy!
      membership.user.api_tokens.usable.where(publisher:).find_each(&:revoke!)
      AuditEvent.record!(actor: Current.user, action: "org.member_remove", subject: publisher,
        metadata: { member: membership.user.email_address })
    end
    redirect_to dashboard_path, notice: "Removed #{membership.user.name || membership.user.email_address} from #{publisher.name}; their tokens for this namespace are revoked."
  end
end
