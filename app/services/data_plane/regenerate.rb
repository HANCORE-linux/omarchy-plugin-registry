module DataPlane
  # Regenerates the static index. Cheap at Omarchy's scale — the whole index
  # can be rebuilt on every publish (the crates.io degenerate case).
  class Regenerate
    def self.plugin(plugin)
      new.write_plugin_index(plugin)
      all
    end

    def self.all
      generator = new
      generator.write_config
      generator.write_all_listing
      generator.write_revocations
      Plugin.find_each do |p|
        generator.write_plugin_index(p)
        generator.restore_missing_tarballs(p)
      end
    end

    # Full regeneration must be able to rebuild the ENTIRE data plane from the
    # database — indexes that reference tarballs the directory doesn't hold
    # would 404 (or worse, a sync --delete would drop survivors).
    def restore_missing_tarballs(plugin)
      plugin.versions.where(state: [ :published, :yanked ]).find_each do |version|
        next if DataPlane.root.join(version.tarball_path).exist?
        next unless version.tarball.attached?
        DataPlane.freeze_tarball(version, version.tarball.download)
      end
    end

    # Freshness horizons: signed files carry generated_at/expires_at so a
    # stale or rolled-back CDN/object-store copy stops verifying. The kill
    # list regenerates every 10 minutes and expires fastest — clients fail
    # CLOSED on an expired revocation list.
    REVOCATIONS_TTL = 24.hours
    INDEX_TTL = 7.days

    # One strictly-increasing generation per regeneration run: clients order
    # signed files by this integer (timestamps can collide within a second).
    def generation
      @generation ||= RegistryCounter.next!("data_plane_generation")
    end

    def freshness(ttl)
      { "generation" => generation,
        "generated_at" => Time.current.utc.iso8601,
        "expires_at" => ttl.from_now.utc.iso8601 }
    end

    def write_config
      # The public key is served unsigned (trust root — clients pin it);
      # everything else carries a detached .sig made with this key.
      key_path = DataPlane.root.join("signing-key.pub")
      FileUtils.mkdir_p(DataPlane.root)
      key_path.write(Signer.public_key_base64)

      DataPlane.write("config.json", JSON.pretty_generate({
        "dl" => "#{DataPlane.base_url}/dl/{publisher}/{name}/{name}-{version}.tar.gz",
        "index" => "#{DataPlane.base_url}/index/{publisher}/{name}.json",
        "revocations" => "#{DataPlane.base_url}/revocations.json",
        "signing_key" => "#{DataPlane.base_url}/signing-key.pub",
        "api" => DataPlane.base_url
      }.merge(freshness(INDEX_TTL))))
    end

    # One JSON line per version, append-only in spirit: every version ever
    # created appears; only published/yanked are useful to clients, and yanked
    # versions stay listed (with the flag) for reproducibility. The first line
    # is a meta record carrying the freshness horizon.
    def write_plugin_index(plugin)
      lines = [ JSON.generate({ "meta" => true }.merge(freshness(INDEX_TTL))) ]
      lines += plugin.versions.where(state: [ :published, :yanked ])
        .order(:version_sort_key).map { |v| JSON.generate(version_entry(v)) }
      DataPlane.write("index/#{plugin.publisher.name}/#{plugin.name}.json", lines.join("\n") + "\n")
    end

    def write_all_listing
      plugins = Plugin.listed.includes(:publisher).filter_map do |plugin|
        next unless plugin.latest_version
        {
          "publisher" => plugin.publisher.name,
          "name" => plugin.name,
          "id" => plugin.manifest_id,
          "summary" => plugin.summary,
          "kinds" => plugin.kinds,
          "latest" => plugin.latest_version,
          "downloads" => plugin.downloads_count
        }
      end
      DataPlane.write("all.json", JSON.generate({ "plugins" => plugins }.merge(freshness(INDEX_TTL))))
    end

    def write_revocations
      entries = Revocation.includes(plugin: :publisher).order(:created_at).map(&:as_kill_list_entry)
      DataPlane.write("revocations.json", JSON.pretty_generate(
        { "schemaVersion" => 1, "revocations" => entries }.merge(freshness(REVOCATIONS_TTL))))
    end

    private

    def version_entry(version)
      {
        "id" => version.plugin.manifest_id,
        "vers" => version.version,
        "sha256" => version.sha256,
        "size" => version.size_bytes,
        "yanked" => version.yanked?,
        "license" => version.license,
        "minOmarchyVersion" => version.min_omarchy_version,
        "kinds" => version.manifest["kinds"],
        "caps" => version.capability_fingerprint
      }.compact
    end
  end
end
