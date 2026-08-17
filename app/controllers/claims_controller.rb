# Grandfathering seeded namespaces: prove control of the listed source repo,
# take ownership of the publisher. Repo-proof happens exactly once. The
# challenge token is derived from publisher + claiming user, so tokens are
# useless to anyone but the account that displayed them.
class ClaimsController < ApplicationController
  before_action :set_publisher

  def show
    @challenge = Registry::RepoProof.challenge_for(@publisher, Current.user)
    @claim_url = Registry::RepoProof.raw_claim_url(@publisher.seed_source_url)
  end

  def verify
    challenge = Registry::RepoProof.challenge_for(@publisher, Current.user)
    if Registry::RepoProof.verified?(@publisher.seed_source_url, challenge)
      ApplicationRecord.transaction do
        @publisher.update!(claimed: true)
        Membership.create!(publisher: @publisher, user: Current.user, role: :owner)
        AuditEvent.record!(actor: Current.user, action: "publisher.claim_seeded", subject: @publisher,
          public: true, metadata: { name: @publisher.name, source: @publisher.seed_source_url })
      end
      redirect_to dashboard_path, notice: "#{@publisher.name} is yours. You can delete #{Registry::RepoProof::CLAIM_FILE} from the repo now."
    else
      redirect_to claim_path(@publisher.name),
        alert: "Couldn't find your token in #{Registry::RepoProof::CLAIM_FILE} on the default branch yet. Give the forge a minute and try again."
    end
  end

  private

  def set_publisher
    @publisher = Publisher.find_by!(name: params[:name])
    redirect_to publisher_path(@publisher.name), alert: "This namespace is already claimed." if @publisher.claimed?
  end
end
