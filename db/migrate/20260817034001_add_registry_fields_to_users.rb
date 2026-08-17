class AddRegistryFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users do |t|
      t.string :name
      t.string :otp_secret
      t.datetime :otp_enabled_at
      t.json :otp_backup_codes
      t.boolean :admin, null: false, default: false
      t.datetime :suspended_at
      # npm-style cooldown: publishing is blocked briefly after sensitive account changes
      t.datetime :sensitive_change_at
    end
  end
end
