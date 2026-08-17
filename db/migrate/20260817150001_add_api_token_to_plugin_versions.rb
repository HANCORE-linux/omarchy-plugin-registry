class AddApiTokenToPluginVersions < ActiveRecord::Migration[8.1]
  def change
    add_reference :plugin_versions, :api_token, foreign_key: true, null: true
  end
end
