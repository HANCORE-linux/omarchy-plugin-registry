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

  # Every index file gets a detached Ed25519 signature at <path>.sig.
  def write(relative_path, content)
    path = root.join(relative_path)
    FileUtils.mkdir_p(path.dirname)
    path.open("wb") { |f| f.write(content) }
    root.join("#{relative_path}.sig").open("wb") { |f| f.write(Signer.sign_base64(content)) }
    path
  end

  # Tarballs are immutable: same bytes may be re-frozen idempotently (release
  # retries), different bytes for an existing path can never land.
  def freeze_tarball(version, bytes)
    path = root.join(version.tarball_path)
    if path.exist?
      return path if Digest::SHA256.file(path).hexdigest == Digest::SHA256.hexdigest(bytes)
      raise ArgumentError, "refusing to overwrite frozen tarball with different bytes: #{version.tarball_path}"
    end
    FileUtils.mkdir_p(path.dirname)
    path.open("wb") { |f| f.write(bytes) }
    path
  end

  def read(relative_path)
    root.join(relative_path).read
  end
end
