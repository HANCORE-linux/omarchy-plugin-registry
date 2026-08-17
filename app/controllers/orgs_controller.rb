class OrgsController < ApplicationController
  before_action :require_recent_second_factor, only: %i[add_member remove_member]
  # Namespaces are first-claim and burned forever — throttle bulk squatting
  rate_limit to: 5, within: 1.day, only: :create,
    with: -> { redirect_to dashboard_path, alert: "Org creation is limited to a few per day." }

  def new
    @publisher = Publisher.new(kind: :org)
  end

  def create
    @publisher = Publisher.new(name: params.dig(:publisher, :name).to_s.downcase.strip,
      display_name: params.dig(:publisher, :display_name), kind: :org)
    if @publisher.save
      Membership.create!(publisher: @publisher, user: Current.user, role: :owner)
      AuditEvent.record!(actor: Current.user, action: "org.create", subject: @publisher,
        public: true, metadata: { name: @publisher.name })
      redirect_to dashboard_path, notice: "Org #{@publisher.name} created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  # Add a member by email (owner only)
  def add_member
    publisher = Publisher.org.find(params[:id])
    return head :forbidden unless Current.user.owner_of?(publisher)

    user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)
    if user.nil?
      redirect_to dashboard_path, alert: "No account with that email."
    elsif publisher.memberships.exists?(user:)
      redirect_to dashboard_path, alert: "Already a member."
    else
      Membership.create!(publisher:, user:, role: params[:role] == "owner" ? :owner : :publisher)
      AuditEvent.record!(actor: Current.user, action: "org.member_add", subject: publisher,
        metadata: { member: user.email_address })
      redirect_to dashboard_path, notice: "Added #{user.name} to #{publisher.name}."
    end
  end

  # A departed or compromised member must be removable — and their scoped
  # tokens die with the membership.
  def remove_member
    publisher = Publisher.org.find(params[:id])
    return head :forbidden unless Current.user.owner_of?(publisher)

    membership = publisher.memberships.find(params[:membership_id])
    if membership.role_owner? && publisher.memberships.owner.count == 1
      return redirect_to dashboard_path, alert: "An org needs at least one owner."
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
