class DashboardController < ApplicationController
  # The one-time minted-token reveal must never land in a shared cache
  after_action { response.headers["Cache-Control"] = "no-store" }

  def show
    @user = Current.user
    @publishers = @user.publishers.includes(:plugins)
    @tokens = @user.api_tokens.usable.order(created_at: :desc)
  end
end
