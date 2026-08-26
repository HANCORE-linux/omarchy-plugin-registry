class AddRepoStatsToPlugins < ActiveRecord::Migration[8.1]
  def change
    # Best-effort GitHub enrichment (stars, last push, latest release) —
    # display-only, refreshed by RepoStatsSweepJob, never part of the signed
    # index or any trust decision.
    add_column :plugins, :repo_stats, :json, default: {}, null: false
    add_column :plugins, :repo_stats_synced_at, :datetime
  end
end
