class FullRegistryBuild < ActiveRecord::Migration[8.1]
  def change
    # --- Review pipeline ---
    change_table :plugin_versions do |t|
      t.datetime :hold_until            # publish hold window (worm brake)
      t.json :scan_results              # deterministic scanner + AI review output
      t.json :provenance                # repo/commit/workflow for OIDC publishes
    end

    # --- Community ---
    change_table :plugins do |t|
      t.integer :views_count, null: false, default: 0
      t.integer :ratings_count, null: false, default: 0
      t.integer :ratings_sum, null: false, default: 0
      t.integer :comments_count, null: false, default: 0
    end

    create_table :ratings do |t|
      t.references :plugin, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :value, null: false
      t.timestamps
    end
    add_index :ratings, [ :plugin_id, :user_id ], unique: true

    create_table :comments do |t|
      t.references :plugin, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.datetime :hidden_at
      t.timestamps
    end
    add_index :comments, [ :plugin_id, :created_at ]

    create_table :reports do |t|
      t.references :user, null: false, foreign_key: true
      t.references :reportable, polymorphic: true, null: false
      t.string :reason, null: false
      t.datetime :resolved_at
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    # --- Trusted publishing (OIDC) ---
    create_table :trusted_publishers do |t|
      t.references :publisher, null: false, foreign_key: true
      t.string :plugin_name, null: false
      t.string :provider, null: false, default: "github"
      t.string :repository, null: false      # owner/repo
      t.string :workflow, null: false        # .github/workflows/publish.yml
      t.string :environment, null: false, default: "release"
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :trusted_publishers, [ :publisher_id, :plugin_name ], unique: true

    add_column :api_tokens, :provenance, :json

    # --- Device flow (CLI login) ---
    create_table :device_authorizations do |t|
      t.string :device_code_digest, null: false
      t.string :user_code, null: false
      t.integer :status, null: false, default: 0
      t.references :user, foreign_key: true            # set at approval
      t.references :publisher, foreign_key: true       # scope chosen at approval
      t.string :plugin_name
      t.string :token_ciphertext                       # minted token held until polled
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :device_authorizations, :device_code_digest, unique: true
    add_index :device_authorizations, :user_code, unique: true

    # --- Passkeys ---
    add_column :users, :webauthn_id, :string
    create_table :passkeys do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :public_key, null: false
      t.bigint :sign_count, null: false, default: 0
      t.string :nickname
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :passkeys, :external_id, unique: true

    # --- Namespace claiming (seeded publishers) ---
    add_column :publishers, :claim_challenge, :string
  end
end
