module Registry
  # One plugin's repo-stats refresh. Serialized globally so a sweep can't
  # burst-drain the GitHub rate budget; a rate-limited or flaky response just
  # leaves the previous stats standing until the next sweep.
  class RepoStatsJob < ApplicationJob
    queue_as :default
    limits_concurrency to: 1, key: "repo_stats"

    def perform(plugin)
      RepoStats.sync!(plugin)
    rescue RepoStats::SyncError
      # Best-effort: stale display data is fine, retry storms are not.
    end
  end
end
