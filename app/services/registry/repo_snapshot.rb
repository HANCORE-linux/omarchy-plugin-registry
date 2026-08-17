require "open3"

module Registry
  # Snapshots a public git repo's HEAD into tarball bytes for seeding.
  # Shallow clone, tracked files only, no hooks run.
  class RepoSnapshot
    class SnapshotError < StandardError; end

    def self.tarball_for(repo_url)
      Dir.mktmpdir("registry-seed") do |dir|
        clone = File.join(dir, "repo")
        run! "git", "clone", "--depth", "1", "--quiet", repo_url, clone
        out, status = Open3.capture2("git", "-C", clone, "archive", "--format=tar.gz", "HEAD")
        raise SnapshotError, "git archive failed for #{repo_url}" unless status.success?
        out
      end
    end

    def self.run!(*command)
      _out, err, status = Open3.capture3(*command)
      raise SnapshotError, "#{command.first} failed: #{err.strip.first(200)}" unless status.success?
    end
  end
end
