# A registered CI identity allowed to publish a plugin with no stored secret:
# repo + workflow + pinned environment, PyPI trusted-publisher style. Rows can
# exist before the plugin does ("pending publishers") — the first CI publish
# creates it.
class TrustedPublisher < ApplicationRecord
  PROVIDERS = %w[github].freeze
  # Resurrection-attack mitigations: pull_request runs fork code, and
  # pull_request_target/workflow_run run in another context's blast radius.
  # None of them mint tokens.
  FORBIDDEN_EVENTS = %w[pull_request pull_request_target workflow_run].freeze

  belongs_to :publisher
  belongs_to :created_by, class_name: "User"

  validates :provider, inclusion: { in: PROVIDERS }
  validates :plugin_name, presence: true, format: { with: NameRules::NAME_FORMAT },
    uniqueness: { scope: :publisher_id }
  validates :repository, presence: true, format: { with: %r{\A[\w.-]+/[\w.-]+\z} }
  validates :workflow, presence: true, format: { with: %r{\A\.github/workflows/[\w.-]+\.ya?ml\z} }
  validates :environment, presence: true

  # The environment binding is GitHub's `sub` contract: a job that runs in a
  # pinned environment carries sub = "repo:<owner>/<repo>:environment:<env>".
  # That is the primary check — the top-level environment claim is redundant
  # confirmation when present, never a substitute. workflow_ref identifies the
  # caller workflow on direct runs; on reusable-workflow runs job_workflow_ref
  # points at the called workflow instead, and when present it must ALSO match
  # — a registered workflow delegating to an arbitrary reusable workflow does
  # not get to mint tokens.
  def matches?(claims)
    claims["repository"].to_s.downcase == repository.downcase &&
      claims["sub"].to_s.downcase == "repo:#{repository.downcase}:environment:#{environment.downcase}" &&
      workflow_ref_matches?(claims["workflow_ref"]) &&
      (claims["job_workflow_ref"].blank? || workflow_ref_matches?(claims["job_workflow_ref"])) &&
      (claims["environment"].blank? || claims["environment"] == environment) &&
      # Releases publish from tags — a modified workflow on a random branch
      # (any collaborator can push one) must not mint tokens even if the
      # environment protection is misconfigured.
      claims["ref"].to_s.start_with?("refs/tags/") &&
      FORBIDDEN_EVENTS.exclude?(claims["event_name"])
  end

  private

  # GitHub repo owner/name are case-insensitive; the WORKFLOW PATH is a real
  # file path and case-sensitive — a case-variant workflow is a different
  # file and must never satisfy the allowlist.
  def workflow_ref_matches?(ref)
    owner, name, rest = ref.to_s.split("/", 3)
    return false if rest.blank?
    "#{owner}/#{name}".downcase == repository.downcase && rest.start_with?("#{workflow}@")
  end
end
