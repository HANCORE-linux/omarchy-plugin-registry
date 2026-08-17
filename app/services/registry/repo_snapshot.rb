require "open3"
require "resolv"

module Registry
  # Snapshots a public git repo's HEAD into tarball bytes for seeding.
  # Shallow clone over https only, tracked files only, no hooks run, bounded
  # in time and size, and never against private/internal addresses.
  class RepoSnapshot
    class SnapshotError < StandardError; end

    CLONE_TIMEOUT = 180 # seconds

    def self.tarball_for(repo_url)
      validate_url!(repo_url)
      Dir.mktmpdir("registry-seed") do |dir|
        clone = File.join(dir, "repo")
        run! "git", "-c", "transfer.fsckObjects=true", "clone", "--depth", "1", "--quiet",
          "--", repo_url, clone
        out, status = Open3.capture2("git", "-C", clone, "archive", "--format=tar.gz", "HEAD")
        raise SnapshotError, "git archive failed for #{repo_url}" unless status.success?
        raise SnapshotError, "snapshot exceeds size limit" if out.bytesize > TarballInspector::MAX_TARBALL_BYTES
        out
      end
    end

    def self.validate_url!(repo_url)
      uri = URI.parse(repo_url.to_s)
      raise SnapshotError, "repository must be an https URL" unless uri.is_a?(URI::HTTPS) && uri.host.present?
      raise SnapshotError, "repository URL must not carry credentials" if uri.userinfo.present?
      addresses = Resolv.getaddresses(uri.host)
      raise SnapshotError, "could not resolve #{uri.host}" if addresses.empty?
      addresses.each do |address|
        ip = IPAddr.new(address)
        if ip.loopback? || ip.private? || ip.link_local?
          raise SnapshotError, "repository host resolves to a private address"
        end
      end
    rescue URI::InvalidURIError, IPAddr::InvalidAddressError
      raise SnapshotError, "invalid repository URL: #{repo_url}"
    end

    def self.run!(*command)
      Timeout.timeout(CLONE_TIMEOUT) do
        _out, err, status = Open3.capture3({ "GIT_TERMINAL_PROMPT" => "0" }, *command)
        raise SnapshotError, "#{command.first} failed: #{err.strip.first(200)}" unless status.success?
      end
    rescue Timeout::Error
      raise SnapshotError, "clone timed out"
    end
  end
end
