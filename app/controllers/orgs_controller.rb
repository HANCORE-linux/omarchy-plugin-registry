class OrgsController < ApplicationController
  def new
    @publisher = Publisher.new(kind: :org)
  end

  def create
    @publisher = Publisher.new(name: params.dig(:publisher, :name).to_s.downcase.strip,
      display_name: params.dig(:publisher, :display_name), kind: :org)
    if @publisher.save
      Membership.create!(publisher: @publisher, user: Current.user, role: :owner)
      AuditEvent.record!(actor: Current.user, action: "org.create", subject: @publisher)
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
end
