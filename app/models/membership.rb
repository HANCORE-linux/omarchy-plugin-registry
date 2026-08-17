class Membership < ApplicationRecord
  belongs_to :publisher
  belongs_to :user

  enum :role, { publisher: 0, owner: 1 }, scopes: false, prefix: :role
  scope :owner, -> { where(role: :owner) }

  validates :user_id, uniqueness: { scope: :publisher_id }
end
