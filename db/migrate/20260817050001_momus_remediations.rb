class MomusRemediations < ActiveRecord::Migration[8.1]
  def change
    # Claim challenges are now derived (HMAC of publisher+user), not stored
    remove_column :publishers, :claim_challenge, :string

    # Brute-force lockout for emailed sign-in codes
    add_column :login_codes, :attempts, :integer, null: false, default: 0

    # Step-up: sensitive actions require a second factor verified in THIS session
    add_column :sessions, :second_factor_verified_at, :datetime

    # Recompute sort keys — prerelease encoding changed to order numerically
    reversible do |direction|
      direction.up do
        execute("SELECT id, version FROM plugin_versions").each do |row|
          key = Semver.parse(row["version"]).sort_key
          execute ActiveRecord::Base.sanitize_sql([ "UPDATE plugin_versions SET version_sort_key = ? WHERE id = ?", key, row["id"] ])
        end
      end
    end
  end
end
