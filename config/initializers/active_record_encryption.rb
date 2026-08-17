# At-rest encryption keys derived from secret_key_base — TOTP seeds must not
# be readable out of a leaked database or backup. Rotating secret_key_base
# rotates these; publishers would re-enroll TOTP (backup codes are digests).
Rails.application.config.active_record.encryption.tap do |encryption|
  key_generator = ActiveSupport::KeyGenerator.new(
    Rails.application.secret_key_base, iterations: 1000, hash_digest_class: OpenSSL::Digest::SHA256
  )
  encryption.primary_key = key_generator.generate_key("active_record_encryption_primary", 32).unpack1("H*")
  encryption.deterministic_key = key_generator.generate_key("active_record_encryption_deterministic", 32).unpack1("H*")
  encryption.key_derivation_salt = key_generator.generate_key("active_record_encryption_salt", 32).unpack1("H*")
end
