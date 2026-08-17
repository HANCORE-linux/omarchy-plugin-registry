class Plugin < ApplicationRecord
  # security_holding: name burned after a malware takedown — page shows a notice,
  # nothing installable, name can never be resurrected.
  enum :state, { active: 0, quarantined: 1, security_holding: 2 }

  belongs_to :publisher
  has_many :versions, class_name: "PluginVersion", dependent: :restrict_with_error
  has_many :revocations, dependent: :restrict_with_error
  has_many :ratings, dependent: :destroy
  has_many :comments, dependent: :destroy
  has_many :reports, as: :reportable, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :publisher_id },
    length: { maximum: NameRules::MAX_LENGTH },
    format: { with: NameRules::NAME_FORMAT, message: "must be lowercase letters, digits, - or _" }

  before_validation { self.normalized_name = NameRules.normalize(name) }

  scope :listed, -> { where(state: :active) }

  # The manifest id installed clients use: today's dot-convention made a rule.
  def manifest_id = "#{publisher.name}.#{name}"

  def full_name = "#{publisher.name}/#{name}"

  def latest_published_version
    versions.published.order(version_sort_key: :desc).first
  end

  # Any version ever created — published, yanked, or rejected — burns name@version.
  def version_burned?(version_string)
    versions.exists?(version: version_string)
  end

  def highest_version
    versions.order(version_sort_key: :desc).first
  end

  def installable? = active? && versions.published.exists?

  def refresh_latest_version!
    update!(latest_version: latest_published_version&.version)
  end

  def average_rating
    return nil if ratings_count.zero?
    (ratings_sum.to_f / ratings_count).round(1)
  end

  def record_view!
    self.class.where(id: id).update_all("views_count = views_count + 1")
  end
end
