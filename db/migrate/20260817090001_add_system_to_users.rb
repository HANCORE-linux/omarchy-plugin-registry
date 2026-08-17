class AddSystemToUsers < ActiveRecord::Migration[8.1]
  def change
    # The seed principal is identified by an explicit flag, not a collidable
    # email address.
    add_column :users, :system, :boolean, null: false, default: false
  end
end
