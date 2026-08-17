class AddApprovalToPluginVersions < ActiveRecord::Migration[8.1]
  def change
    add_column :plugin_versions, :approved_at, :datetime
    add_reference :plugin_versions, :approved_by, foreign_key: { to_table: :users }, null: true
  end
end
