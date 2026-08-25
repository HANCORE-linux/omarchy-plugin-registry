# Short-lived, push-only. Account-wide by default (like RubyGems/npm): the
# token can publish to any namespace its user is a member of, which the publish
# path enforces via membership regardless of the token. A non-null publisher
# and/or plugin_name NARROWS the scope — trusted publishing (OIDC) mints
# per-plugin tokens for CI. The plaintext token exists only at mint time; we
# store a SHA-256 digest. No long-lived classic tokens, ever.
class ApiToken < ApplicationRecord
  DEFAULT_TTL = 7.days
  MAX_TTL = 90.days
  PREFIX = "omp_"

  belongs_to :user
  belongs_to :publisher, optional: true

  attr_reader :plaintext_token
  # Machine-minted tokens (OIDC exchange) don't consume the user-managed quota
  attr_accessor :quota_exempt

  MAX_USABLE_PER_USER = 25

  validates :plugin_name, format: { with: NameRules::NAME_FORMAT },
    length: { maximum: NameRules::MAX_LENGTH }, allow_nil: true
  # A plugin-scoped token must also name its namespace — plugin without
  # publisher is a nonsense scope.
  validates :publisher, presence: true, if: -> { plugin_name.present? }
  validates :expires_at, presence: true
  validate :ttl_within_bounds, on: :create
  validate :usable_quota, on: :create
  validate :publisher_not_suspended, on: :create

  scope :usable, -> { where(revoked_at: nil).where(expires_at: Time.current..) }

  def self.mint!(user:, publisher: nil, plugin_name: nil, ttl: DEFAULT_TTL, quota_exempt: false)
    raw = PREFIX + SecureRandom.base58(30)
    token = create!(
      user:, publisher:, plugin_name:,
      token_digest: digest(raw),
      token_hint: "#{raw.first(8)}…#{raw.last(4)}",
      expires_at: ttl.from_now,
      quota_exempt: quota_exempt
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

  # Scope is a widening hierarchy: account-wide (no publisher) authorizes any
  # target, namespace-wide (publisher, no plugin) authorizes any plugin in it,
  # per-plugin authorizes exactly one. Membership is enforced separately at
  # publish time, so an account-wide token can still only reach the user's own
  # namespaces.
  def authorizes?(publisher_arg, plugin_name_arg)
    return true if publisher_id.nil?
    return false unless publisher_id == publisher_arg.id
    plugin_name.nil? || plugin_name == plugin_name_arg
  end

  # Human-readable scope for tokens list / API responses.
  def scope_label
    return "account (any of your namespaces)" if publisher_id.nil?
    plugin_name.nil? ? "#{publisher.name}/*" : "#{publisher.name}/#{plugin_name}"
  end

  private

  def ttl_within_bounds
    errors.add(:expires_at, "exceeds maximum lifetime") if expires_at && expires_at > MAX_TTL.from_now
  end

  def usable_quota
    return if quota_exempt
    # Machine-minted (OIDC/provenance) tokens neither consume nor count toward
    # the user-managed quota — a CI burst must not lock a human out
    if user && user.api_tokens.usable.where(provenance: nil).count >= MAX_USABLE_PER_USER
      errors.add(:base, "too many active tokens — revoke some first")
    end
  end

  # No stockpiling seven-day tokens against a suspended namespace to spend
  # the moment it's reinstated
  def publisher_not_suspended
    errors.add(:base, "publisher is suspended") if publisher&.suspended?
  end
end
