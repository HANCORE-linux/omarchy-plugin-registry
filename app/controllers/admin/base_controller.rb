module Admin
  class BaseController < ApplicationController
    before_action :require_admin

    private

    def require_admin
      head :not_found unless Current.user&.admin?
    end
  end
end
