# One-time sign-in code for passwordless auth (the Cortex/Herald MagicLink
# pattern): 6 digits, emailed, 15-minute expiry, single use.
class LoginCode < ApplicationRecord
  CODE_LENGTH = 6
  EXPIRATION = 15.minutes

  belongs_to :user

  before_create { self.code = SecureRandom.random_number(10**CODE_LENGTH).to_s.rjust(CODE_LENGTH, "0") }

  scope :active, -> { where(consumed_at: nil).where(created_at: EXPIRATION.ago..) }

  def expired? = created_at < EXPIRATION.ago

  def consume!
    raise ActiveRecord::RecordInvalid, self if expired? || consumed_at.present?
    update!(consumed_at: Time.current)
  end
end
