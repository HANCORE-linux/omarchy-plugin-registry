module Admin
  class BaseController < ApplicationController
    before_action :require_admin
    # Admin powers (approve, revoke, burn namespaces) need a session-verified
    # second factor, not just an emailed sign-in code — and they wait out the
    # sensitive-change cooldown, so a factor enrolled through 72-hour recovery
    # can't immediately wield takedown powers.
    before_action :require_recent_second_factor
    before_action :require_no_sensitive_cooldown

    private

    def require_admin
      head :not_found unless Current.user&.admin?
    end
  end
end
