class CreatePublishers < ActiveRecord::Migration[8.1]
  def change
    create_table :publishers do |t|
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.integer :kind, null: false, default: 0
      t.string :display_name
      t.string :website
      t.text :bio
      t.boolean :verified, null: false, default: false
      t.datetime :suspended_at
      # Seeding from omarchyplugins.com: unclaimed publishers hold seeded plugins
      # until someone proves control of the listed source repo.
      t.boolean :claimed, null: false, default: true
      t.string :seed_source_url
      t.timestamps
    end
    add_index :publishers, :name, unique: true
    add_index :publishers, :normalized_name, unique: true

    create_table :memberships do |t|
      t.references :publisher, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :role, null: false, default: 0
      t.timestamps
    end
    add_index :memberships, [ :publisher_id, :user_id ], unique: true
  end
end
