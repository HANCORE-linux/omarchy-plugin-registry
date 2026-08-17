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
      Plugin.find_each { |p| generator.write_plugin_index(p) }
    end

    def write_config
      DataPlane.write("config.json", JSON.pretty_generate(
        "dl" => "#{DataPlane.base_url}/dl/{publisher}/{name}/{name}-{version}.tar.gz",
        "index" => "#{DataPlane.base_url}/index/{publisher}/{name}.json",
        "revocations" => "#{DataPlane.base_url}/revocations.json",
        "api" => DataPlane.base_url
      ))
    end

    # One JSON line per version, append-only in spirit: every version ever
    # created appears; only published/yanked are useful to clients, and yanked
    # versions stay listed (with the flag) for reproducibility.
    def write_plugin_index(plugin)
      lines = plugin.versions.where(state: [ :published, :yanked ])
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
      DataPlane.write("all.json", JSON.generate("plugins" => plugins, "generated_at" => Time.current.utc.iso8601))
    end

    def write_revocations
      entries = Revocation.includes(plugin: :publisher).order(:created_at).map(&:as_kill_list_entry)
      DataPlane.write("revocations.json", JSON.pretty_generate("schemaVersion" => 1, "revocations" => entries))
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
