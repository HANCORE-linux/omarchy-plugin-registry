class MomusRoundThree < ActiveRecord::Migration[8.1]
  def change
    # Trust-on-first-use pins for GitHub's immutable repo/owner IDs — a
    # transferred or recreated owner/name can't keep minting tokens.
    add_column :trusted_publishers, :repository_id, :string
    add_column :trusted_publishers, :repository_owner_id, :string

    # Sort-key encoding changed again (identifier joiner must sort below "-")
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
