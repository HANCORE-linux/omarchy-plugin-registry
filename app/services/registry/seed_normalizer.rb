require "rubygems/package"
require "zlib"

module Registry
  # Rewrites a seeded snapshot's manifest into registry form before it enters
  # the publish pipeline. Legacy marketplace manifests carry ids in every
  # convention except ours (`publisher.name`), predate the curated taxonomy,
  # and — when fetched via GitHub's archive endpoint — arrive wrapped in a
  # `owner-repo-sha/` prefix directory. This pass:
  #
  #   * strips a single common prefix directory when the manifest lives there,
  #   * rewrites manifest `id` to `publisher.plugin-name`, preserving the
  #     original as `legacyId` (the client-side migration key for installs
  #     made through the legacy marketplace),
  #   * injects curated category/tags from the legacy listing when the
  #     manifest declares none (they lived in the marketplace's registry.json,
  #     never in author manifests),
  #
  # and repacks. The output is a registry-authored artifact either way — the
  # sha256 of record is computed on what THIS produces, and the version's
  # provenance names the source repo + commit it was derived from.
  class SeedNormalizer
    class NormalizeError < StandardError; end

    MANIFEST_NAME = "manifest.json"

    # legacy_id is the manifest id the plugin shipped under on the legacy
    # marketplace (nil when it already matched registry form) — the caller
    # records it in provenance and the client migration map.
    Result = Struct.new(:bytes, :legacy_id)

    def self.normalize(bytes, publisher_name:, plugin_name:, category: nil, tags: nil)
      new(bytes, publisher_name:, plugin_name:, category:, tags:).normalize
    end

    def initialize(bytes, publisher_name:, plugin_name:, category: nil, tags: nil)
      @bytes = bytes
      @publisher_name = publisher_name
      @plugin_name = plugin_name
      @category = category
      @tags = tags
    end

    def normalize
      files = read_files
      files = strip_prefix(files)
      manifest_entry = files.find { |f| f[:path] == MANIFEST_NAME }
      raise NormalizeError, "snapshot has no root #{MANIFEST_NAME}" if manifest_entry.nil?

      manifest = parse_manifest(manifest_entry[:content])
      legacy_id = rewrite!(manifest)
      manifest_entry[:content] = JSON.pretty_generate(manifest) + "\n"
      Result.new(repack(files), legacy_id)
    end

    private

    # Tolerant read: directories and PAX headers are dropped (GitHub archives
    # emit them; the repack recreates none), as are link/device entries —
    # TarballInspector re-validates the OUTPUT strictly, so nothing structural
    # is trusted from here.
    def read_files
      files = []
      unpacked = 0
      Zlib::GzipReader.wrap(StringIO.new(@bytes)) do |gz|
        Gem::Package::TarReader.new(gz) do |tar|
          tar.each do |entry|
            next unless entry.file?
            unpacked += entry.header.size
            raise NormalizeError, "snapshot exceeds unpacked size limit" if unpacked > TarballInspector::MAX_UNPACKED_BYTES
            raise NormalizeError, "snapshot has too many entries" if files.length >= TarballInspector::MAX_ENTRIES
            files << { path: entry.full_name.sub(%r{\A\./}, ""), mode: entry.header.mode, content: entry.read.to_s }
          end
        end
      end
      raise NormalizeError, "snapshot is empty" if files.empty?
      files
    rescue Zlib::Error, Gem::Package::TarInvalidError => e
      raise NormalizeError, "snapshot is not a valid tar.gz: #{e.message.first(120)}"
    end

    def strip_prefix(files)
      return files if files.any? { |f| f[:path] == MANIFEST_NAME }
      prefixes = files.map { |f| f[:path].split("/").first }.uniq
      return files unless prefixes.length == 1
      prefix = "#{prefixes.first}/"
      return files unless files.any? { |f| f[:path] == "#{prefix}#{MANIFEST_NAME}" }
      files.filter_map do |f|
        stripped = f[:path].delete_prefix(prefix)
        next if stripped.empty?
        f.merge(path: stripped)
      end
    end

    def parse_manifest(content)
      manifest = JSON.parse(content)
      raise NormalizeError, "#{MANIFEST_NAME} is not a JSON object" unless manifest.is_a?(Hash)
      manifest
    rescue JSON::ParserError => e
      raise NormalizeError, "#{MANIFEST_NAME} is not valid JSON: #{e.message.first(120)}"
    end

    # Returns the preserved legacy id (nil when none needed preserving).
    def rewrite!(manifest)
      registry_id = "#{@publisher_name}.#{@plugin_name}"
      original_id = manifest["id"].to_s
      legacy_id = original_id.present? && original_id != registry_id ? original_id : nil
      manifest["legacyId"] = legacy_id if legacy_id
      manifest["id"] = registry_id
      # Curation only fills gaps — an author who declared their own valid
      # category/tags keeps them. Invalid legacy values are dropped, not
      # failed: taxonomy is a browse aid, not a publish gate for seeds.
      if manifest["category"].blank? && @category.present? && Taxonomy.category?(@category)
        manifest["category"] = @category
      end
      if manifest["tags"].blank? && @tags.present?
        curated = Array(@tags).select { |t| Taxonomy.tag?(t) }.uniq.first(Taxonomy::MAX_TAGS)
        manifest["tags"] = curated if curated.any?
      end
      legacy_id
    end

    def repack(files)
      out = StringIO.new
      out.set_encoding(Encoding::BINARY)
      Zlib::GzipWriter.wrap(out) do |gz|
        Gem::Package::TarWriter.new(gz) do |tar|
          files.each do |f|
            tar.add_file_simple(f[:path], f[:mode] & 0o777, f[:content].bytesize) do |io|
              io.write(f[:content])
            end
          end
        end
      end
      out.string
    rescue Gem::Package::TooLongFileName => e
      raise NormalizeError, "snapshot contains a path too long to repack: #{e.message.first(120)}"
    end
  end
end
