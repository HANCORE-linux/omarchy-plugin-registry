require "open3"
require "resolv"

module Registry
  # Snapshots a public git repo's HEAD into tarball bytes for seeding.
  # Shallow clone over https only, tracked files only, no hooks run, bounded
  # in time and size, and never against private/internal addresses.
  class RepoSnapshot
    class SnapshotError < StandardError; end

    CLONE_TIMEOUT = 180 # seconds
    MAX_CLONE_BYTES = 100 * 1024 * 1024

    def self.tarball_for(repo_url)
      validate_url!(repo_url)
      Dir.mktmpdir("registry-seed") do |dir|
        clone = File.join(dir, "repo")
        # blob:limit keeps oversized current blobs out of the transfer where the
        # server supports partial clone; the on-disk quota is the backstop.
        # followRedirects=false closes the redirect-after-validation gap.
        # (Residual DNS-rebinding TOCTOU is accepted: seeding is an
        # operator-run task over a curated catalog, not attacker-triggered.)
        run! "git", "-c", "transfer.fsckObjects=true", "-c", "http.followRedirects=false",
          "clone", "--depth", "1", "--filter=blob:limit=10m", "--quiet", "--", repo_url, clone
        enforce_clone_quota!(clone, repo_url)
        bounded_archive(clone, repo_url)
      end
    end

    def self.enforce_clone_quota!(clone, repo_url)
      bytes = Dir.glob(File.join(clone, "**", "*"), File::FNM_DOTMATCH)
        .sum { |f| File.file?(f) ? File.size(f) : 0 }
      raise SnapshotError, "clone of #{repo_url} exceeds the #{MAX_CLONE_BYTES / 1024 / 1024}MB disk quota" if bytes > MAX_CLONE_BYTES
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

    # Reads the archive incrementally and aborts the moment it exceeds the
    # size cap — an oversized repo can't balloon runner memory first.
    def self.bounded_archive(clone, repo_url)
      out = +""
      # GIT_ALLOW_PROTOCOL=file: archiving must never lazy-fetch filtered blobs
      # over the network — a filtered-out oversized blob fails the archive
      # instead of bypassing the transfer limits.
      IO.popen([ { "GIT_ALLOW_PROTOCOL" => "file" }, "git", "-C", clone, "archive", "--format=tar.gz", "HEAD" ], "rb") do |io|
        while (chunk = io.read(64 * 1024))
          out << chunk
          if out.bytesize > TarballInspector::MAX_TARBALL_BYTES
            Process.kill("TERM", io.pid) rescue nil
            raise SnapshotError, "snapshot exceeds size limit"
          end
        end
      end
      raise SnapshotError, "git archive failed for #{repo_url}" unless $?.success?
      out
    end

    # Timeout enforcement actually KILLS the child — a hung clone must not
    # outlive its deadline as an orphaned git process.
    def self.run!(*command)
      Open3.popen3({ "GIT_TERMINAL_PROMPT" => "0" }, *command) do |stdin, _stdout, stderr, wait_thread|
        stdin.close
        err_reader = Thread.new { stderr.read(64 * 1024).to_s }
        unless wait_thread.join(CLONE_TIMEOUT)
          Process.kill("KILL", wait_thread.pid) rescue nil
          wait_thread.join(5)
          raise SnapshotError, "clone timed out"
        end
        unless wait_thread.value.success?
          raise SnapshotError, "#{command.first} failed: #{err_reader.value.strip.first(200)}"
        end
      end
    end
  end
end
