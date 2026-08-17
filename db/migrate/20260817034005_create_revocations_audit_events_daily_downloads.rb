class CreateRevocationsAuditEventsDailyDownloads < ActiveRecord::Migration[8.1]
  def change
    # The kill list. Rows here are serialized into revocations.json on the data
    # plane; the client disables matching installed plugins. version nil = whole plugin.
    create_table :revocations do |t|
      t.references :plugin, null: false, foreign_key: true
      t.string :version
      t.string :reason, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :revocations, [ :plugin_id, :version ], unique: true

    create_table :audit_events do |t|
      t.references :user, foreign_key: true # nil = system
      t.string :action, null: false
      t.references :subject, polymorphic: true, null: false
      t.json :metadata, null: false, default: {}
      # Public events appear on the transparency log page
      t.boolean :public, null: false, default: false
      t.timestamps
    end
    add_index :audit_events, [ :public, :created_at ]

    create_table :daily_downloads do |t|
      t.references :plugin_version, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :count, null: false, default: 0
    end
    add_index :daily_downloads, [ :plugin_version_id, :date ], unique: true
  end
end
