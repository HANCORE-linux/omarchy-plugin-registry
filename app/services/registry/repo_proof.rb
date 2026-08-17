require "net/http"

module Registry
  # One-time proof of control of a seeded plugin's source repo: the claimant
  # commits `.omarchy-claim` containing their challenge token to the default
  # branch, and we fetch it raw over HTTPS. Used ONLY for grandfathering seeded
  # namespaces — after the claim, ordinary account ownership takes over.
  class RepoProof
    CLAIM_FILE = ".omarchy-claim".freeze

    RAW_URL_PATTERNS = {
      %r{\Ahttps://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?\z} =>
        ->(m) { "https://raw.githubusercontent.com/#{m[1]}/#{m[2]}/HEAD/#{CLAIM_FILE}" },
      %r{\Ahttps://codeberg\.org/([^/]+)/([^/]+?)(?:\.git)?/?\z} =>
        ->(m) { "https://codeberg.org/#{m[1]}/#{m[2]}/raw/branch/HEAD/#{CLAIM_FILE}" },
      %r{\Ahttps://gitlab\.com/([^/]+)/([^/]+?)(?:\.git)?/?\z} =>
        ->(m) { "https://gitlab.com/#{m[1]}/#{m[2]}/-/raw/HEAD/#{CLAIM_FILE}" }
    }.freeze

    def self.fetcher
      Rails.application.config.x.repo_proof_fetcher || method(:http_get)
    end

    def self.verified?(repo_url, expected_token)
      url = raw_claim_url(repo_url)
      return false if url.nil? || expected_token.blank?
      body = fetcher.call(url)
      body.to_s.strip == expected_token
    end

    def self.raw_claim_url(repo_url)
      RAW_URL_PATTERNS.each do |pattern, builder|
        match = pattern.match(repo_url.to_s)
        return builder.call(match) if match
      end
      nil
    end

    def self.http_get(url, limit = 3)
      return nil if limit.zero?
      response = Net::HTTP.get_response(URI(url))
      case response
      when Net::HTTPSuccess then response.body
      when Net::HTTPRedirection then http_get(response["location"], limit - 1)
      end
    end
  end
end
