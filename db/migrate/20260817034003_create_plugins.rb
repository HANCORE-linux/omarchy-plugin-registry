class CreatePlugins < ActiveRecord::Migration[8.1]
  def change
    create_table :plugins do |t|
      t.references :publisher, null: false, foreign_key: true
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.string :summary
      t.string :repository_url
      t.string :homepage_url
      # active | quarantined | security_holding (name burned after malware takedown)
      t.integer :state, null: false, default: 0
      t.text :readme
      t.json :kinds, null: false, default: []
      t.integer :downloads_count, null: false, default: 0
      t.string :latest_version
      t.timestamps
    end
    add_index :plugins, [ :publisher_id, :name ], unique: true
    add_index :plugins, :normalized_name

    create_table :plugin_versions do |t|
      t.references :plugin, null: false, foreign_key: true
      t.string :version, null: false
      # Zero-padded sort key so "0.9.0" < "0.10.0" without semver math in SQL
      t.string :version_sort_key, null: false
      t.json :manifest, null: false
      t.string :sha256, null: false
      t.integer :size_bytes, null: false
      t.string :license
      t.string :min_omarchy_version
      # processing | published | held | quarantined | yanked | rejected
      # Rows are never deleted: a name@version is burned forever, whatever its fate.
      t.integer :state, null: false, default: 0
      t.datetime :published_at
      t.datetime :yanked_at
      t.string :yank_reason
      t.text :review_notes
      t.json :capability_fingerprint
      t.integer :downloads_count, null: false, default: 0
      t.timestamps
    end
    add_index :plugin_versions, [ :plugin_id, :version ], unique: true
  end
end
