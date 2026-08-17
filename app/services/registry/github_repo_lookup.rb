require "net/http"

module Registry
  # Resolves a repo's immutable numeric identity at REGISTRATION time, so a
  # transferred or recreated owner/name can never satisfy trusted publishing —
  # not even before the first exchange.
  class GithubRepoLookup
    class LookupError < StandardError; end

    def self.identity_for(repository)
      if (override = Rails.application.config.x.github_repo_lookup)
        return override.call(repository)
      end

      response = Net::HTTP.get_response(URI("https://api.github.com/repos/#{repository}"),
        { "Accept" => "application/vnd.github+json", "User-Agent" => "plugins.omarchy.org" })
      raise LookupError, "GitHub returned #{response.code} for #{repository}" unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      { repository_id: data.fetch("id").to_s, repository_owner_id: data.fetch("owner").fetch("id").to_s }
    rescue JSON::ParserError, KeyError, SocketError, Timeout::Error => e
      raise LookupError, "could not resolve #{repository}: #{e.message}"
    end
  end
end
