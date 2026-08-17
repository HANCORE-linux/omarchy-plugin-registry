# Short-lived, push-only, scoped to one plugin name in one namespace.
# The plaintext token exists only at mint time; we store a SHA-256 digest.
# No long-lived classic tokens, ever.
class ApiToken < ApplicationRecord
  DEFAULT_TTL = 7.days
  MAX_TTL = 90.days
  PREFIX = "omp_"

  belongs_to :user
  belongs_to :publisher

  attr_reader :plaintext_token

  validates :plugin_name, presence: true, format: { with: NameRules::NAME_FORMAT }
  validates :expires_at, presence: true
  validate :ttl_within_bounds, on: :create

  scope :usable, -> { where(revoked_at: nil).where(expires_at: Time.current..) }

  def self.mint!(user:, publisher:, plugin_name:, ttl: DEFAULT_TTL)
    raw = PREFIX + SecureRandom.base58(30)
    token = create!(
      user:, publisher:, plugin_name:,
      token_digest: digest(raw),
      token_hint: "#{raw.first(8)}…#{raw.last(4)}",
      expires_at: ttl.from_now
    )
    token.instance_variable_set(:@plaintext_token, raw)
    token
  end

  def self.authenticate(raw)
    return nil if raw.blank?
    usable.find_by(token_digest: digest(raw))&.tap { |t| t.touch(:last_used_at) }
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw)

  def revoke! = update!(revoked_at: Time.current)

  def usable? = revoked_at.nil? && expires_at.future?

  def authorizes?(publisher_arg, plugin_name_arg)
    publisher_id == publisher_arg.id && plugin_name == plugin_name_arg
  end

  private

  def ttl_within_bounds
    errors.add(:expires_at, "exceeds maximum lifetime") if expires_at && expires_at > MAX_TTL.from_now
  end
end
