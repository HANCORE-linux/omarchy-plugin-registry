class MomusRoundSeven < ActiveRecord::Migration[8.1]
  def change
    # Versions remember who submitted them — release re-checks that principal
    add_reference :plugin_versions, :user, foreign_key: true
  end
end
