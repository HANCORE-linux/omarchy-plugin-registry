class Membership < ApplicationRecord
  belongs_to :publisher
  belongs_to :user

  enum :role, { publisher: 0, owner: 1 }, scopes: false, prefix: :role
  scope :owner, -> { where(role: :owner) }
  # Invitations don't grant anything until accepted
  scope :accepted, -> { where.not(accepted_at: nil) }
  scope :pending, -> { where(accepted_at: nil) }

  validates :user_id, uniqueness: { scope: :publisher_id }

  # Founding memberships are self-created — consent is implicit
  before_validation { self.accepted_at ||= Time.current if founding? }

  def pending? = accepted_at.nil?

  def accept!
    update!(accepted_at: Time.current)
  end
end
