# One-time sign-in code for passwordless auth (the Cortex/Herald MagicLink
# pattern): 6 digits, emailed, 15-minute expiry, single use.
class LoginCode < ApplicationRecord
  CODE_LENGTH = 6
  EXPIRATION = 15.minutes
  MAX_ATTEMPTS = 5

  belongs_to :user

  # Only the digest is persisted — a read-only database disclosure yields no
  # working sign-in codes. Plaintext exists in memory at creation (for the
  # email) and nowhere else.
  attr_reader :plaintext_code

  before_create do
    @plaintext_code = SecureRandom.random_number(10**CODE_LENGTH).to_s.rjust(CODE_LENGTH, "0")
    self.code = self.class.digest(@plaintext_code)
  end

  def self.digest(plaintext) = Digest::SHA256.hexdigest(plaintext.to_s)

  scope :active, -> { where(consumed_at: nil).where(created_at: EXPIRATION.ago..) }
  scope :redeemable, -> { where(attempts: ...MAX_ATTEMPTS) }

  def expired? = created_at < EXPIRATION.ago

  def consume!
    raise ActiveRecord::RecordInvalid, self if expired? || consumed_at.present?
    update!(consumed_at: Time.current)
  end
end
