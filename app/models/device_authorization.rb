# CLI login without ever typing credentials into a terminal (RFC 8628 shape):
# `omarchy plugin publish` requests a code pair, the user approves the 8-char
# user code in the browser (MFA'd session), and the CLI polls until it
# receives a freshly minted scoped token. The token plaintext is held
# encrypted only until the CLI claims it, then wiped.
class DeviceAuthorization < ApplicationRecord
  EXPIRATION = 15.minutes
  USER_CODE_ALPHABET = "BCDFGHJKLMNPQRSTVWXZ23456789".chars.freeze # no lookalikes
  POLL_INTERVAL = 5 # seconds, advisory for clients

  enum :status, { pending: 0, approved: 1, denied: 2, claimed: 3 }

  belongs_to :user, optional: true
  belongs_to :publisher, optional: true

  attr_reader :plaintext_device_code

  scope :active, -> { where(expires_at: Time.current..) }

  def self.start!
    raw = "omd_" + SecureRandom.base58(30)
    authorization = create!(
      device_code_digest: digest(raw),
      user_code: generate_user_code,
      expires_at: EXPIRATION.from_now
    )
    authorization.instance_variable_set(:@plaintext_device_code, raw)
    authorization
  end

  def self.find_by_device_code(raw)
    active.find_by(device_code_digest: digest(raw.to_s))
  end

  def self.find_by_user_code(code)
    active.pending.find_by(user_code: normalize_user_code(code))
  end

  def self.digest(raw) = Digest::SHA256.hexdigest(raw)

  def self.normalize_user_code(code)
    cleaned = code.to_s.upcase.gsub(/[^A-Z0-9]/, "")
    "#{cleaned[0, 4]}-#{cleaned[4, 4]}"
  end

  def approve!(user:, publisher:, plugin_name:)
    token = ApiToken.mint!(user:, publisher:, plugin_name:)
    update!(status: :approved, user:, publisher:, plugin_name:,
      token_ciphertext: self.class.encryptor.encrypt_and_sign(token.plaintext_token))
    token
  end

  def deny!(user:)
    update!(status: :denied, user:)
  end

  # One-shot: the atomic status flip decides the single winner among
  # concurrent polls; only the winner decrypts.
  def claim!
    ciphertext = token_ciphertext
    claimed_rows = self.class.where(id: id, status: :approved)
      .update_all(status: :claimed, token_ciphertext: nil)
    raise ActiveRecord::RecordInvalid, self unless claimed_rows == 1 && ciphertext.present?
    self.class.encryptor.decrypt_and_verify(ciphertext)
  end

  def expired? = expires_at.past?

  def self.encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(
      Rails.application.key_generator.generate_key("device_authorization_tokens", 32)
    )
  end

  def self.generate_user_code
    code = Array.new(8) { USER_CODE_ALPHABET.sample }.join
    "#{code[0, 4]}-#{code[4, 4]}"
  end
end
