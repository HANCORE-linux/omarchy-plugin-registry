require "rubygems/package"
require "zlib"

module Registry
  # Safely inspects an uploaded .tar.gz without trusting it: enforces size and
  # entry limits, rejects symlinks/hardlinks/devices, absolute paths, and path
  # traversal. Never extracts to disk — reads manifest and readme in memory.
  class TarballInspector
    class InvalidTarball < StandardError; end

    MAX_TARBALL_BYTES = 10.megabytes
    MAX_UNPACKED_BYTES = 50.megabytes
    MAX_ENTRIES = 2_000
    MANIFEST_NAME = "manifest.json"
    README_CANDIDATES = %w[README.md readme.md README Readme.md].freeze

    # Per-file cap on content retained for scanning; larger files keep only
    # their first MAX_SCAN_BYTES (the scanner flags oversized/binary blobs anyway).
    MAX_SCAN_BYTES = 512.kilobytes

    attr_reader :manifest, :readme, :files, :contents, :digests, :truncated, :sha256, :size_bytes

    def self.inspect_bytes(bytes)
      new(bytes).tap(&:inspect!)
    end

    def initialize(bytes)
      @bytes = bytes
    end

    def inspect!
      @size_bytes = @bytes.bytesize
      raise InvalidTarball, "tarball is empty" if @size_bytes.zero?
      raise InvalidTarball, "tarball exceeds #{MAX_TARBALL_BYTES / 1.megabyte}MB limit" if @size_bytes > MAX_TARBALL_BYTES

      @sha256 = Digest::SHA256.hexdigest(@bytes)
      @files = []
      @contents = {}
      @digests = {} # full-content SHA-256 per file — diffing must never rely on the truncated scan window
      @truncated = []
      manifest_json = nil
      readme_content = nil
      unpacked = 0

      entry_count = 0
      each_tar_entry do |entry|
        # Count EVERY entry (directories included) so an archive can't smuggle
        # unbounded headers past a files-only limit.
        entry_count += 1
        raise InvalidTarball, "too many entries" if entry_count > MAX_ENTRIES

        path = clean_path(entry.full_name)
        case
        when entry.directory?
          next
        when entry.symlink? || entry.header.typeflag == "1"
          raise InvalidTarball, "symlinks and hardlinks are not allowed (#{path})"
        when !entry.file?
          raise InvalidTarball, "unsupported entry type for #{path}"
        end

        unpacked += entry.header.size
        raise InvalidTarball, "unpacked size exceeds limit" if unpacked > MAX_UNPACKED_BYTES

        # Duplicate paths would let reviewed bytes differ from unpacked bytes
        # depending on which entry a consumer picks — never ambiguous.
        raise InvalidTarball, "duplicate path in tarball: #{path}" if @contents.key?(path)

        @files << path
        content = entry.read.to_s
        @digests[path] = Digest::SHA256.hexdigest(content)
        @truncated << path if content.bytesize > MAX_SCAN_BYTES
        @contents[path] = content.byteslice(0, MAX_SCAN_BYTES)
        manifest_json = content if path == MANIFEST_NAME
        readme_content ||= content.dup.force_encoding(Encoding::UTF_8) if README_CANDIDATES.include?(path)
      end

      raise InvalidTarball, "#{MANIFEST_NAME} missing at tarball root" if manifest_json.nil?
      @manifest = parse_manifest(manifest_json)
      @readme = readme_content&.valid_encoding? ? readme_content : nil
      self
    rescue Zlib::Error, Gem::Package::TarInvalidError => e
      raise InvalidTarball, "not a valid gzipped tarball: #{e.message}"
    end

    def include?(path) = files.include?(path)

    private

    def each_tar_entry(&block)
      Zlib::GzipReader.wrap(StringIO.new(@bytes)) do |gz|
        Gem::Package::TarReader.new(gz) { |tar| tar.each(&block) }
      end
    end

    # Normalize to canonical root-relative paths — "./x", "././x", and "a//b"
    # must collapse to the same path extraction would produce, or duplicate
    # detection can be sidestepped. Escapes are refused outright.
    def clean_path(raw)
      raise InvalidTarball, "illegal path in tarball: #{raw.inspect}" if raw.include?("\0") || raw.start_with?("/")
      segments = raw.split("/").reject { |segment| segment == "." || segment.empty? }
      raise InvalidTarball, "illegal path in tarball: #{raw.inspect}" if segments.empty? || segments.include?("..")
      segments.join("/")
    end

    def parse_manifest(json)
      raise InvalidTarball, "#{MANIFEST_NAME} exceeds 64KB" if json.bytesize > 64.kilobytes
      parsed = JSON.parse(json)
      raise InvalidTarball, "#{MANIFEST_NAME} must be a JSON object" unless parsed.is_a?(Hash)
      parsed
    rescue JSON::ParserError => e
      raise InvalidTarball, "#{MANIFEST_NAME} is not valid JSON: #{e.message}"
    end
  end
end
