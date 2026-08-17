class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :publishers, through: :memberships
  has_many :api_tokens, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true

  # Publishing is blocked for a cooldown window after sensitive account changes
  # (email, password, MFA reset) — the npm post-worm posture.
  PUBLISH_COOLDOWN = 12.hours

  def personal_publisher
    publishers.merge(Publisher.personal).first
  end

  def otp_enabled? = otp_enabled_at.present?

  def can_publish?
    otp_enabled? && suspended_at.nil? && !in_publish_cooldown?
  end

  def in_publish_cooldown?
    sensitive_change_at.present? && sensitive_change_at > PUBLISH_COOLDOWN.ago
  end

  def provision_otp!
    update!(otp_secret: ROTP::Base32.random)
    otp_secret
  end

  def otp_provisioning_uri
    ROTP::TOTP.new(otp_secret, issuer: "plugins.omarchy.org").provisioning_uri(email_address)
  end

  def enable_otp!(code)
    return false unless verify_otp(code)
    update!(otp_enabled_at: Time.current, otp_backup_codes: generate_backup_codes)
    true
  end

  def verify_otp(code)
    return false if otp_secret.blank?
    ROTP::TOTP.new(otp_secret).verify(code.to_s.remove(/\s/), drift_behind: 15).present? ||
      consume_backup_code(code)
  end

  def owner_of?(publisher)
    memberships.exists?(publisher: publisher, role: :owner)
  end

  def member_of?(publisher)
    memberships.exists?(publisher: publisher)
  end

  private

  def generate_backup_codes
    Array.new(8) { SecureRandom.alphanumeric(10).downcase }
  end

  def consume_backup_code(code)
    codes = otp_backup_codes || []
    return false unless codes.include?(code.to_s)
    update!(otp_backup_codes: codes - [ code.to_s ])
    true
  end
end
