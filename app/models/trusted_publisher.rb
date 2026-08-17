# A registered CI identity allowed to publish a plugin with no stored secret:
# repo + workflow + pinned environment, PyPI trusted-publisher style. Rows can
# exist before the plugin does ("pending publishers") — the first CI publish
# creates it.
class TrustedPublisher < ApplicationRecord
  PROVIDERS = %w[github].freeze
  # Resurrection-attack mitigations: these trigger in the context of another
  # repo's code and must never mint tokens.
  FORBIDDEN_EVENTS = %w[pull_request_target workflow_run].freeze

  belongs_to :publisher
  belongs_to :created_by, class_name: "User"

  validates :provider, inclusion: { in: PROVIDERS }
  validates :plugin_name, presence: true, format: { with: NameRules::NAME_FORMAT },
    uniqueness: { scope: :publisher_id }
  validates :repository, presence: true, format: { with: %r{\A[\w.-]+/[\w.-]+\z} }
  validates :workflow, presence: true, format: { with: %r{\A\.github/workflows/[\w.-]+\.ya?ml\z} }
  validates :environment, presence: true

  # workflow_ref identifies the caller workflow on direct runs; on reusable-
  # workflow runs job_workflow_ref points at the called workflow instead. We
  # pin the registered workflow via workflow_ref, and when job_workflow_ref is
  # present it must ALSO match — a registered workflow that delegates to an
  # arbitrary reusable workflow does not get to mint tokens.
  def matches?(claims)
    expected_prefix = "#{repository}/#{workflow}@"
    claims["repository"] == repository &&
      claims["workflow_ref"].to_s.start_with?(expected_prefix) &&
      (claims["job_workflow_ref"].blank? || claims["job_workflow_ref"].to_s.start_with?(expected_prefix)) &&
      claims["environment"] == environment &&
      FORBIDDEN_EVENTS.exclude?(claims["event_name"])
  end
end
