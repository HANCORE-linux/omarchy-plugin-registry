class AddApiTokenToDeviceAuthorizations < ActiveRecord::Migration[8.1]
  def change
    add_reference :device_authorizations, :api_token, foreign_key: true, null: true
  end
end
