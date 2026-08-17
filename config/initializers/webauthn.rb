WebAuthn.configure do |config|
  config.allowed_origins = [ Rails.application.config.x.registry_base_url ]
  config.rp_name = "plugins.omarchy.org"
end
