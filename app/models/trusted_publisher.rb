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

  def matches?(claims)
    claims["repository"] == repository &&
      claims["job_workflow_ref"].to_s.start_with?("#{repository}/#{workflow}@") &&
      claims["environment"] == environment &&
      FORBIDDEN_EVENTS.exclude?(claims["event_name"])
  end
end
