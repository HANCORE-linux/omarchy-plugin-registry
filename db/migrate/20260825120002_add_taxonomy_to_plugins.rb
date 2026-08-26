class AddTaxonomyToPlugins < ActiveRecord::Migration[8.1]
  def change
    # Copied from the latest published manifest by refresh_latest_version! —
    # like summary/kinds, only cleared code ever shapes these.
    add_column :plugins, :category, :string
    add_column :plugins, :tags, :json, default: [], null: false
    add_index :plugins, :category
  end
end
