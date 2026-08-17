class AddVerifiedAtToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :verified_at, :datetime
    # Anyone who exists before this migration predates the pending-account
    # purge — grandfather them in as verified
    execute "UPDATE users SET verified_at = created_at"
  end

  def down
    remove_column :users, :verified_at
  end
end
