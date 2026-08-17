class TrustedPublishersController < ApplicationController
  before_action :require_recent_second_factor
  before_action :require_no_sensitive_cooldown, only: :create
  # Each registration performs a GitHub API lookup — quota it
  rate_limit to: 10, within: 1.hour, only: :create,
    with: -> { redirect_to dashboard_path, alert: "Too many registrations — try again later." }

  def create
    publisher = Current.user.publishers.find_by!(name: params[:publisher_name])
    return redirect_to dashboard_path, alert: "Only namespace owners can register trusted publishers." unless Current.user.owner_of?(publisher)

    repository = params[:repository].to_s.strip
    unless repository.match?(%r{\A[\w.-]+/[\w.-]+\z})
      return redirect_to dashboard_path, alert: "Repository must look like owner/name."
    end
    begin
      identity = Registry::GithubRepoLookup.identity_for(repository)
    rescue Registry::GithubRepoLookup::LookupError => e
      return redirect_to dashboard_path, alert: "Couldn't verify the repository on GitHub: #{e.message}"
    end

    trusted = TrustedPublisher.new(
      publisher:,
      plugin_name: params[:plugin_name].to_s.downcase.strip,
      repository: repository,
      repository_id: identity[:repository_id],
      repository_owner_id: identity[:repository_owner_id],
      workflow: params[:workflow].to_s.strip,
      environment: params[:environment].presence || "release",
      created_by: Current.user
    )
    if trusted.save
      AuditEvent.record!(actor: Current.user, action: "trusted_publisher.create", subject: trusted,
        metadata: { scope: "#{publisher.name}/#{trusted.plugin_name}", repository: trusted.repository })
      redirect_to dashboard_path, notice: "Trusted publishing enabled: #{trusted.repository} → #{publisher.name}/#{trusted.plugin_name}."
    else
      redirect_to dashboard_path, alert: trusted.errors.full_messages.join("; ")
    end
  end

  def destroy
    trusted = TrustedPublisher.find(params[:id])
    return head :forbidden unless Current.user.owner_of?(trusted.publisher)
    ApplicationRecord.transaction do
      # Tokens the registration minted die with it — a token exchanged seconds
      # before removal must not keep publishing for its remaining lifetime
      ApiToken.usable.where(publisher: trusted.publisher, plugin_name: trusted.plugin_name)
        .where.not(provenance: nil).find_each(&:revoke!)
      trusted.destroy!
    end
    AuditEvent.record!(actor: Current.user, action: "trusted_publisher.remove", subject: trusted.publisher,
      metadata: { scope: "#{trusted.publisher.name}/#{trusted.plugin_name}" })
    redirect_to dashboard_path, notice: "Trusted publisher removed."
  end
end
