require "rubygems/package"
require "zlib"

# Builds real .tar.gz bytes for publish-pipeline tests.
module TarballBuilder
  DEFAULT_MANIFEST = {
    "schemaVersion" => 1,
    "id" => "acme.weather",
    "name" => "Weather",
    "version" => "1.0.0",
    "kinds" => [ "bar-widget" ],
    "entryPoints" => { "barWidget" => "Widget.qml" },
    "license" => "MIT"
  }.freeze

  module_function

  def build(manifest: DEFAULT_MANIFEST, files: { "Widget.qml" => "import QtQuick\nItem {}\n" }, symlink: nil)
    io = StringIO.new
    Zlib::GzipWriter.wrap(io) do |gz|
      Gem::Package::TarWriter.new(gz) do |tar|
        if manifest
          json = manifest.to_json
          tar.add_file_simple("manifest.json", 0o644, json.bytesize) { |f| f.write(json) }
        end
        files.each do |path, content|
          tar.add_file_simple(path, 0o644, content.bytesize) { |f| f.write(content) }
        end
        tar.add_symlink(symlink[:name], symlink[:target], 0o644) if symlink
      end
    end
    io.string
  end

  def manifest(**overrides)
    DEFAULT_MANIFEST.merge(overrides.transform_keys(&:to_s))
  end
end
