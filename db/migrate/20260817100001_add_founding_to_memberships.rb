class AddFoundingToMemberships < ActiveRecord::Migration[8.1]
  def change
    # The cooldown exemption belongs to an explicit founding marker, not a
    # timestamp-window heuristic.
    add_column :memberships, :founding, :boolean, null: false, default: false
  end
end
