class AddAcceptedAtToMemberships < ActiveRecord::Migration[8.1]
  def change
    # Membership requires consent: rows are invitations until accepted
    add_column :memberships, :accepted_at, :datetime
    reversible do |direction|
      direction.up { execute "UPDATE memberships SET accepted_at = created_at" }
    end
  end
end
