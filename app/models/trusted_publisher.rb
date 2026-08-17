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
    expected_prefix = "#{repository}/#{workflow}@"
    claims["repository"] == repository &&
      claims["sub"] == "repo:#{repository}:environment:#{environment}" &&
      claims["workflow_ref"].to_s.start_with?(expected_prefix) &&
      (claims["job_workflow_ref"].blank? || claims["job_workflow_ref"].to_s.start_with?(expected_prefix)) &&
      (claims["environment"].blank? || claims["environment"] == environment) &&
      FORBIDDEN_EVENTS.exclude?(claims["event_name"])
  end
end
