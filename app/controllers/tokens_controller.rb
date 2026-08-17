class TokensController < ApplicationController
  def create
    publisher = Current.user.publishers.find_by!(name: params[:publisher_name])
    plugin_name = params[:plugin_name].to_s.downcase.strip

    unless plugin_name.match?(NameRules::NAME_FORMAT)
      return redirect_to dashboard_path, alert: "Plugin name must be lowercase letters, digits, - or _"
    end
    unless Current.user.second_factor?
      return redirect_to settings_two_factor_path, alert: "Add a passkey or enable two-factor authentication before minting publish tokens."
    end

    token = ApiToken.mint!(user: Current.user, publisher:, plugin_name:)
    flash[:minted_token] = token.plaintext_token
    redirect_to dashboard_path, notice: "Token minted — copy it now, it won't be shown again. Expires in 7 days."
  end

  def destroy
    Current.user.api_tokens.find(params[:id]).revoke!
    redirect_to dashboard_path, notice: "Token revoked."
  end
end
