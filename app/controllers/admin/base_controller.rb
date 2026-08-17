module Admin
  class BaseController < ApplicationController
    before_action :require_admin
    # Admin powers (approve, revoke, burn namespaces) need a session-verified
    # second factor, not just an emailed sign-in code.
    before_action :require_recent_second_factor

    private

    def require_admin
      head :not_found unless Current.user&.admin?
    end
  end
end
