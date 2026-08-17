class UniqueWholePluginRevocations < ActiveRecord::Migration[8.1]
  def change
    # SQL NULLs are distinct, so the (plugin_id, version) unique index never
    # stopped duplicate whole-plugin revocations — a partial index does.
    add_index :revocations, :plugin_id, unique: true, where: "version IS NULL",
      name: "index_revocations_whole_plugin_uniqueness"
  end
end
