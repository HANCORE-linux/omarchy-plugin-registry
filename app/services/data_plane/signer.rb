module DataPlane
  # Detached Ed25519 signatures over every index file — clients verify the
  # index (which carries tarball checksums), so the whole chain is covered.
  # The kill list especially must be unforgeable.
  #
  # Key: REGISTRY_SIGNING_SEED (base64, 32 bytes) in production; dev/test
  # generate and persist one under storage/ so signatures stay stable locally.
  module Signer
    module_function

    def signing_key
      @signing_key ||= Ed25519::SigningKey.new(seed)
    end

    def public_key_base64
      Base64.strict_encode64(signing_key.verify_key.to_bytes)
    end

    def sign_base64(content)
      Base64.strict_encode64(signing_key.sign(content))
    end

    def verify?(content, signature_base64)
      signing_key.verify_key.verify(Base64.strict_decode64(signature_base64), content)
    rescue Ed25519::VerifyError, ArgumentError
      false
    end

    def seed
      if (env_seed = ENV["REGISTRY_SIGNING_SEED"]).present?
        Base64.strict_decode64(env_seed)
      elsif Rails.env.production?
        raise "REGISTRY_SIGNING_SEED is required in production"
      else
        seed_path = Rails.root.join("storage", "#{Rails.env}_signing.seed")
        unless seed_path.exist?
          FileUtils.mkdir_p(seed_path.dirname)
          seed_path.binwrite(Ed25519::SigningKey.generate.seed)
          seed_path.chmod(0o600)
        end
        seed_path.binread
      end
    end

    def reset! = @signing_key = nil
  end
end
