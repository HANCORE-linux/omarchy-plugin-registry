module Registry
  # Daily fan-out: refresh repo stats for every listed plugin whose last sync
  # is stale. Each plugin is its own serialized job, so one bad repo can't
  # stall the rest and the per-request pacing lives in one place.
  class RepoStatsSweepJob < ApplicationJob
    queue_as :default

    STALE_AFTER = 20.hours

    def perform
      Plugin.listed.where.not(repository_url: nil)
        .where("repo_stats_synced_at IS NULL OR repo_stats_synced_at < ?", STALE_AFTER.ago)
        .find_each { |plugin| RepoStatsJob.perform_later(plugin) }
    end
  end
end
