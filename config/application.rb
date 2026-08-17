require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module OmarchyPluginRegistry
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Static data plane output (synced to object storage/CDN in production)
    config.x.data_plane_root = Rails.root.join("storage/data_plane")
    config.x.registry_base_url = ENV.fetch("REGISTRY_BASE_URL", "https://plugins.omarchy.org")

    # Publish hold window: even clean versions wait before going live (worm brake).
    config.x.publish_hold = 15.minutes

    # Shell command for LLM review of submissions (reads JSON on stdin, prints
    # {"verdict":..., "reasons":[...]}). Unset = AI review disabled.
    config.x.ai_review_command = ENV["AI_REVIEW_COMMAND"]

    # Static JWKS override for OIDC trusted publishing (tests inject one;
    # production fetches GitHub's and caches it)
    config.x.github_oidc_jwks = nil

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
