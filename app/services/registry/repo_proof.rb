require "net/http"
require "resolv"

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

    # Challenge tokens are derived per publisher AND per claiming user — no
    # stored state, and one user's token is useless to another, so an attacker
    # who reads the owner's claim page (or the committed file) cannot race the
    # verify step with their own account.
    def self.challenge_for(publisher, user)
      digest = OpenSSL::HMAC.hexdigest("SHA256",
        Rails.application.key_generator.generate_key("repo_claim_challenges", 32),
        "#{publisher.id}:#{user.id}")
      "omarchy-claim-#{digest.first(32)}"
    end

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

    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 5
    MAX_BODY_BYTES = 64 * 1024

    # Bounded and revalidated per hop: explicit timeouts, a body-size cap, and
    # every redirect target re-checked as https-to-a-public-host, so slow or
    # oversized responses (or a redirect into internal address space) go nowhere.
    def self.http_get(url, limit = 3)
      return nil if limit.zero?
      uri = URI(url)
      return nil unless safe_target?(uri)

      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request_get(uri.request_uri) do |response|
          case response
          when Net::HTTPSuccess
            # Stream with a hard cap — never buffer an unbounded body
            body = +""
            response.read_body do |chunk|
              body << chunk
              return body.byteslice(0, MAX_BODY_BYTES) if body.bytesize >= MAX_BODY_BYTES
            end
            return body
          when Net::HTTPRedirection
            return http_get(response["location"], limit - 1)
          else
            return nil
          end
        end
      end
    rescue Timeout::Error, SystemCallError, OpenSSL::SSL::SSLError, SocketError
      nil
    end

    def self.safe_target?(uri)
      return false unless uri.is_a?(URI::HTTPS) && uri.host.present?
      Resolv.getaddresses(uri.host).then do |addresses|
        addresses.any? && addresses.none? do |address|
          ip = IPAddr.new(address)
          ip.loopback? || ip.private? || ip.link_local?
        end
      end
    rescue IPAddr::InvalidAddressError, Resolv::ResolvError
      false
    end
  end
end
