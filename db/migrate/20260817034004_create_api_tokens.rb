class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: true
      # Push-only, scoped to a single plugin name within a publisher namespace.
      # plugin may be nil for a "first publish" token scoped to a not-yet-created name.
      t.references :publisher, null: false, foreign_key: true
      t.string :plugin_name, null: false
      t.string :token_digest, null: false
      t.string :token_hint, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :api_tokens, :token_digest, unique: true
  end
end
