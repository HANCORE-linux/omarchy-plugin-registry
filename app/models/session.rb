class Session < ApplicationRecord
  belongs_to :user

  # A stolen cookie must not work forever: absolute lifetime plus idle window.
  ABSOLUTE_LIFETIME = 30.days
  IDLE_LIFETIME = 14.days

  def expired?
    created_at < ABSOLUTE_LIFETIME.ago || updated_at < IDLE_LIFETIME.ago
  end

  scope :expired, -> {
    where(created_at: ...ABSOLUTE_LIFETIME.ago).or(where(updated_at: ...IDLE_LIFETIME.ago))
  }
end
