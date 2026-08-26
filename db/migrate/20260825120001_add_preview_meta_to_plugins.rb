class AddPreviewMetaToPlugins < ActiveRecord::Migration[8.1]
  def change
    # Dimensions and animation flag for the generated preview renditions —
    # rendered as width/height attributes so cards never layout-shift.
    add_column :plugins, :preview_meta, :json, default: {}, null: false
  end
end
