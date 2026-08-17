# A namespace: either a user's personal handle or an org created in-app.
# Names are first-come-first-served with typosquat checks at claim time.
class Publisher < ApplicationRecord
  enum :kind, { personal: 0, org: 1 }

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :plugins, dependent: :restrict_with_error

  validates :name, presence: true, uniqueness: true,
    length: { maximum: NameRules::MAX_LENGTH },
    format: { with: NameRules::NAME_FORMAT, message: "must be lowercase letters, digits, - or _" }
  validate :name_not_reserved, on: :create
  validate :name_not_confusable, on: :create

  before_validation { self.normalized_name = NameRules.normalize(name) }

  scope :claimed, -> { where(claimed: true) }

  def to_param = name

  def owners = users.merge(Membership.owner)

  def suspended? = suspended_at.present?

  private

  def name_not_reserved
    errors.add(:name, "is reserved") if NameRules.reserved?(name)
  end

  def name_not_confusable
    return if name.blank?
    clash = Publisher.where(normalized_name: NameRules.normalize(name)).where.not(id: id)
    errors.add(:name, "is too similar to existing publisher #{clash.first.name}") if clash.exists?
  end
end
