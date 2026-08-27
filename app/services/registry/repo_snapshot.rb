require "open3"
require "resolv"
require "net/http"

module Registry
  # Snapshots a public git repo's HEAD into tarball bytes for seeding.
  # Shallow clone over https only, tracked files only, no hooks run, bounded
  # in time and size, and never against private/internal addresses.
  class RepoSnapshot
    class SnapshotError < StandardError; end

    CLONE_TIMEOUT = 180 # seconds
    MAX_CLONE_BYTES = 100 * 1024 * 1024
    # GitHub's archive endpoint wraps content in a prefix directory, so the
    # download can run slightly larger than the final repacked tarball cap.
    MAX_ARCHIVE_DOWNLOAD_BYTES = TarballInspector::MAX_TARBALL_BYTES + 2 * 1024 * 1024
    ARCHIVE_TIMEOUT = 120 # seconds

    # With a commit, fetches the exact reviewed snapshot as GitHub's archive
    # tarball (codeload) — the seed importer must never substitute mutable
    # HEAD for the commit the legacy marketplace actually validated. Without
    # one, shallow-clones and archives HEAD as before.
    def self.tarball_for(repo_url, commit = nil)
      return archive_at_commit(repo_url, commit) if commit.present?
      validate_url!(repo_url)
      Dir.mktmpdir("registry-seed") do |dir|
        clone = File.join(dir, "repo")
        # blob:limit keeps oversized current blobs out of the transfer where the
        # server supports partial clone; the on-disk quota is the backstop.
        # followRedirects=false closes the redirect-after-validation gap.
        # (Residual DNS-rebinding TOCTOU is accepted: seeding is an
        # operator-run task over a curated catalog, not attacker-triggered.)
        run_with_disk_quota!(clone,
          "git", "-c", "transfer.fsckObjects=true", "-c", "http.followRedirects=false",
          "clone", "--depth", "1", "--filter=blob:limit=10m", "--quiet", "--", repo_url, clone)
        enforce_clone_quota!(clone, repo_url)
        bounded_archive(clone, repo_url)
      end
    end

    # Exact-commit archives are GitHub-only for now (the whole legacy catalog
    # is on github.com). The tarball carries a `owner-repo-sha/` prefix
    # directory that SeedNormalizer strips during manifest normalization.
    def self.archive_at_commit(repo_url, commit)
      unless commit.to_s.match?(/\A[0-9a-f]{40}\z/)
        raise SnapshotError, "commit must be a full 40-character sha (got #{commit.to_s.first(50)})"
      end
      validate_url!(repo_url)
      owner, repo = URI.parse(repo_url.to_s).path.delete_prefix("/").delete_suffix(".git").split("/")
      unless URI.parse(repo_url.to_s).host == "github.com" && owner.present? && repo.present?
        raise SnapshotError, "exact-commit snapshots are only supported for github.com repositories"
      end
      download_archive(URI("https://codeload.github.com/#{owner}/#{repo}/tar.gz/#{commit}"))
    end

    def self.download_archive(uri)
      out = +""
      Net::HTTP.start(uri.host, uri.port, use_ssl: true,
        open_timeout: 15, read_timeout: ARCHIVE_TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri)) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            raise SnapshotError, "archive download failed (HTTP #{response.code}) for #{uri}"
          end
          response.read_body do |chunk|
            out << chunk
            raise SnapshotError, "archive exceeds size limit" if out.bytesize > MAX_ARCHIVE_DOWNLOAD_BYTES
          end
        end
      end
      raise SnapshotError, "archive download was empty for #{uri}" if out.empty?
      out
    rescue Timeout::Error, SystemCallError, OpenSSL::SSL::SSLError, Net::ProtocolError => e
      raise SnapshotError, "archive download failed for #{uri}: #{e.message.first(200)}"
    end

    def self.enforce_clone_quota!(clone, repo_url)
      if directory_bytes(clone) > MAX_CLONE_BYTES
        raise SnapshotError, "clone of #{repo_url} exceeds the #{MAX_CLONE_BYTES / 1024 / 1024}MB disk quota"
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

    # Reads the archive incrementally and aborts the moment it exceeds the
    # size cap — an oversized repo can't balloon runner memory first.
    def self.bounded_archive(clone, repo_url)
      out = +""
      # GIT_ALLOW_PROTOCOL=file: archiving must never lazy-fetch filtered blobs
      # over the network — a filtered-out oversized blob fails the archive
      # instead of bypassing the transfer limits.
      IO.popen([ { "GIT_ALLOW_PROTOCOL" => "file" }, "git", "-C", clone, "archive", "--format=tar.gz", "HEAD" ], "rb", pgroup: true) do |io|
        while (chunk = io.read(64 * 1024))
          out << chunk
          if out.bytesize > TarballInspector::MAX_TARBALL_BYTES
            Process.kill("TERM", -io.pid) rescue (Process.kill("TERM", io.pid) rescue nil)
            raise SnapshotError, "snapshot exceeds size limit"
          end
        end
      end
      raise SnapshotError, "git archive failed for #{repo_url}" unless $?.success?
      out
    end

    # Timeout AND in-flight disk quota are enforced while the clone runs — the
    # process is killed the moment either is breached, so a server that
    # ignores partial-clone filters (or a many-small-blobs repository) cannot
    # fill the disk before a post-hoc check would notice.
    def self.run_with_disk_quota!(watched_dir, *command)
      Open3.popen3({ "GIT_TERMINAL_PROMPT" => "0" }, *command, pgroup: true) do |stdin, _stdout, stderr, wait_thread|
        stdin.close
        err_reader = Thread.new { stderr.read(64 * 1024).to_s }
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + CLONE_TIMEOUT

        loop do
          break if wait_thread.join(2)
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            kill(wait_thread)
            raise SnapshotError, "clone timed out"
          end
          if directory_bytes(watched_dir) > MAX_CLONE_BYTES
            kill(wait_thread)
            raise SnapshotError, "clone exceeded the #{MAX_CLONE_BYTES / 1024 / 1024}MB disk quota mid-transfer"
          end
        end

        unless wait_thread.value.success?
          raise SnapshotError, "#{command.first} failed: #{err_reader.value.strip.first(200)}"
        end
      end
    end

    def self.kill(wait_thread)
      # Whole process group — git spawns helpers (git-remote-https) that must
      # die with it
      Process.kill("KILL", -wait_thread.pid) rescue (Process.kill("KILL", wait_thread.pid) rescue nil)
      wait_thread.join(5)
    end

    def self.directory_bytes(dir)
      return 0 unless File.directory?(dir)
      Dir.glob(File.join(dir, "**", "*"), File::FNM_DOTMATCH)
        .sum { |f| File.file?(f) ? File.size(f) : 0 }
    rescue SystemCallError
      0
    end
  end
end
