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

      uri = URI("https://api.github.com/repos/#{repository}")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        request = Net::HTTP::Get.new(uri, { "Accept" => "application/vnd.github+json", "User-Agent" => "plugins.omarchy.org" })
        http.request(request)
      end
      raise LookupError, "GitHub returned #{response.code} for #{repository}" unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      { repository_id: data.fetch("id").to_s, repository_owner_id: data.fetch("owner").fetch("id").to_s }
    rescue JSON::ParserError, KeyError, SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => e
      raise LookupError, "could not resolve #{repository}: #{e.message}"
    end
  end
end
