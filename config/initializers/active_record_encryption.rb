# At-rest encryption keys derived from secret_key_base — TOTP seeds must not
# be readable out of a leaked database or backup. When rotating
# secret_key_base, set OLD_SECRET_KEY_BASE for one deploy cycle: previous keys
# keep existing ciphertexts readable while new writes use the new key.
derive = lambda do |secret|
  key_generator = ActiveSupport::KeyGenerator.new(secret, iterations: 1000, hash_digest_class: OpenSSL::Digest::SHA256)
  {
    primary: key_generator.generate_key("active_record_encryption_primary", 32).unpack1("H*"),
    deterministic: key_generator.generate_key("active_record_encryption_deterministic", 32).unpack1("H*"),
    salt: key_generator.generate_key("active_record_encryption_salt", 32).unpack1("H*")
  }
end

Rails.application.config.active_record.encryption.tap do |encryption|
  current = derive.call(Rails.application.secret_key_base)
  encryption.primary_key = current[:primary]
  encryption.deterministic_key = current[:deterministic]
  encryption.key_derivation_salt = current[:salt]

  if ENV["OLD_SECRET_KEY_BASE"].present?
    old = derive.call(ENV["OLD_SECRET_KEY_BASE"])
    encryption.previous = [ { primary_key: old[:primary], deterministic_key: old[:deterministic], key_derivation_salt: old[:salt] } ]
  end
end
