# The static data plane: append-only JSON index + immutable tarballs, written
# to a local directory that production syncs to object storage behind the CDN.
# The Rails app is never in the install hot path — clients read these files.
#
# Layout (all paths relative to DataPlane.root):
#   config.json                      — dl/index URL templates for clients
#   index/<publisher>/<plugin>.json  — one JSON line per version (crates.io style)
#   all.json                         — compact listing for the directory + CLI search
#   revocations.json                 — the kill list (empty almost always)
#   dl/<publisher>/<plugin>/<plugin>-<version>.tar.gz
module DataPlane
  module_function

  def root
    Rails.application.config.x.data_plane_root
  end

  def base_url
    Rails.application.config.x.registry_base_url
  end

  def write(relative_path, content)
    path = root.join(relative_path)
    FileUtils.mkdir_p(path.dirname)
    path.open("wb") { |f| f.write(content) }
    path
  end

  # Tarballs are immutable: an existing file is never rewritten.
  def freeze_tarball(version, bytes)
    path = root.join(version.tarball_path)
    raise ArgumentError, "tarball already frozen: #{version.tarball_path}" if path.exist?
    FileUtils.mkdir_p(path.dirname)
    path.open("wb") { |f| f.write(bytes) }
    path
  end

  def read(relative_path)
    root.join(relative_path).read
  end
end
