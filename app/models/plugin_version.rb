class PluginVersion < ApplicationRecord
  # Rows are never destroyed once created: a name@version is burned forever,
  # even when rejected or yanked — no re-pushes, no same-version-different-bytes.
  enum :state, {
    processing: 0,   # uploaded, running the pipeline
    published: 1,    # live on the data plane
    held: 2,         # waiting out the publish hold window (Phase 2)
    quarantined: 3,  # flagged — visible as "under review", uninstallable
    yanked: 4,       # crates.io semantics: leaves resolution, page shows notice
    rejected: 5      # failed the pipeline; version stays burned
  }

  belongs_to :plugin
  belongs_to :user, optional: true # submitting principal; release re-checks it
  has_many :daily_downloads, dependent: :destroy
  has_one_attached :tarball

  validates :version, presence: true, uniqueness: { scope: :plugin_id }
  validate :version_is_strict_semver

  before_validation { self.version_sort_key = Semver.parse(version).sort_key if Semver.valid?(version) }
  before_destroy { throw :abort } # burned forever

  scope :resolvable, -> { published }

  def semver = Semver.parse(version)

  # States an admin approval or hold expiry may publish from. `processing` is
  # deliberately excluded: nothing publishes before the review pipeline ran.
  def releasable? = held? || quarantined?

  def yank!(reason:, actor:)
    transaction do
      update!(state: :yanked, yanked_at: Time.current, yank_reason: reason)
      plugin.refresh_latest_version!
      AuditEvent.record!(actor:, action: "version.yank", subject: self, public: true,
        metadata: { plugin: plugin.full_name, version:, reason: })
    end
  end

  def tarball_filename = "#{plugin.name}-#{version}.tar.gz"

  # Path on the static data plane, relative to its root.
  def tarball_path = "dl/#{plugin.publisher.name}/#{plugin.name}/#{tarball_filename}"

  private

  def version_is_strict_semver
    errors.add(:version, "must be strict semver (MAJOR.MINOR.PATCH)") unless Semver.valid?(version)
  end
end
