require "net/http"

module Registry
  # Display-only enrichment from the plugin's source repository: stars, last
  # push, latest release. GitHub only for now (the overwhelming majority of
  # manifests) — other hosts simply keep an empty stats hash. Never consulted
  # for any trust or review decision.
  class RepoStats
    class SyncError < StandardError; end

    USER_AGENT = "plugins.omarchy.org"

    def self.sync!(plugin)
      repository = github_repository(plugin.repository_url)
      # Not a GitHub repo (or no repo at all): clear stale stats and stop —
      # the sweep must not retry these forever.
      stats = repository ? fetch(repository) : {}
      plugin.update!(repo_stats: stats, repo_stats_synced_at: Time.current)
    end

    # "https://github.com/owner/repo(.git)" => "owner/repo", else nil.
    def self.github_repository(url)
      uri = URI.parse(url.to_s)
      return nil unless uri.is_a?(URI::HTTPS) && uri.host&.downcase&.delete_prefix("www.") == "github.com"
      owner, repo = uri.path.delete_prefix("/").delete_suffix("/").split("/")
      return nil if owner.blank? || repo.blank?
      "#{owner}/#{repo.delete_suffix('.git')}"
    rescue URI::InvalidURIError
      nil
    end

    def self.fetch(repository)
      if (override = Rails.application.config.x.repo_stats_lookup)
        return override.call(repository)
      end

      repo = get_json("https://api.github.com/repos/#{repository}")
      stats = {
        "stars" => repo["stargazers_count"].to_i,
        "pushed_at" => repo["pushed_at"]
      }
      if (release = get_json("https://api.github.com/repos/#{repository}/releases/latest", missing_ok: true))
        stats["release_tag"] = release["tag_name"]
        stats["release_url"] = release["html_url"]
        stats["release_published_at"] = release["published_at"]
      end
      stats.compact
    end

    def self.get_json(url, missing_ok: false)
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        headers = { "Accept" => "application/vnd.github+json", "User-Agent" => USER_AGENT }
        headers["Authorization"] = "Bearer #{ENV['GITHUB_API_TOKEN']}" if ENV["GITHUB_API_TOKEN"].present?
        http.request(Net::HTTP::Get.new(uri, headers))
      end
      return nil if missing_ok && response.is_a?(Net::HTTPNotFound)
      raise SyncError, "GitHub returned #{response.code} for #{uri.path}" unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body)
    rescue JSON::ParserError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise SyncError, "could not fetch #{url}: #{e.message}"
    end
  end
end
