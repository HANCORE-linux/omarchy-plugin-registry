class AddRequestedScopeToDeviceAuthorizations < ActiveRecord::Migration[8.1]
  def change
    add_column :device_authorizations, :requested_publisher_name, :string
    add_column :device_authorizations, :requested_plugin_name, :string
  end
end
