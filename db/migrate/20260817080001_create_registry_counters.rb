class CreateRegistryCounters < ActiveRecord::Migration[8.1]
  def change
    # Strictly monotonic generation numbers for signed data-plane files —
    # second-resolution timestamps can collide, an integer counter cannot.
    create_table :registry_counters do |t|
      t.string :name, null: false
      t.bigint :value, null: false, default: 0
    end
    add_index :registry_counters, :name, unique: true
  end
end
