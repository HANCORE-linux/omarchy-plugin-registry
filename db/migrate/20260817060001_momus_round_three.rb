class MomusRoundThree < ActiveRecord::Migration[8.1]
  # Frozen copy of the sort-key encoder as of this migration — replay must not
  # depend on the mutable application Semver class.
  SEMVER = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?\z/

  def self.sort_key_for(version)
    match = SEMVER.match(version) or return nil
    key = format("%010d.%010d.%010d", match[1].to_i, match[2].to_i, match[3].to_i)
    return "#{key}~" if match[4].nil?
    encoded = match[4].split(".").map do |identifier|
      identifier.match?(/\A\d+\z/) ? format("0%010d", identifier.to_i) : "1#{identifier}"
    end
    "#{key}-#{encoded.join('!')}"
  end

  def change
    # Trust-on-registration pins for GitHub's immutable repo/owner IDs — a
    # transferred or recreated owner/name can't keep minting tokens.
    add_column :trusted_publishers, :repository_id, :string
    add_column :trusted_publishers, :repository_owner_id, :string

    # Sort-key encoding changed (identifier joiner must sort below "-")
    reversible do |direction|
      direction.up do
        execute("SELECT id, version FROM plugin_versions").each do |row|
          key = self.class.sort_key_for(row["version"]) or next
          execute ActiveRecord::Base.sanitize_sql([ "UPDATE plugin_versions SET version_sort_key = ? WHERE id = ?", key, row["id"] ])
        end
      end
    end
  end
end
