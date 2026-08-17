# Development seed data — runs plugins through the real publish pipeline so the
# data plane, index, and directory all exercise production code paths.
return if Rails.env.production?

require "rubygems/package"
require "zlib"

def build_tarball(manifest, files)
  io = StringIO.new
  Zlib::GzipWriter.wrap(io) do |gz|
    Gem::Package::TarWriter.new(gz) do |tar|
      json = JSON.pretty_generate(manifest)
      tar.add_file_simple("manifest.json", 0o644, json.bytesize) { |f| f.write(json) }
      files.each do |path, content|
        tar.add_file_simple(path, 0o644, content.bytesize) { |f| f.write(content) }
      end
    end
  end
  io.string
end

admin = User.find_or_create_by!(email_address: "ryan@heyoodle.com") do |u|
  u.name = "Ryan Hughes"
  u.admin = true
  u.otp_secret = ROTP::Base32.random
  u.otp_enabled_at = Time.current
end
admin.update!(admin: true) unless admin.admin?

ryan = Publisher.find_or_create_by!(name: "ryanrhughes") { |p| p.kind = :personal }
Membership.find_or_create_by!(publisher: ryan, user: admin) { |m| m.role = :owner }

SAMPLES = [
  { name: "weather", summary: "Current conditions and forecast in your bar, without the bloat.",
    kinds: [ "bar-widget" ], versions: %w[0.9.0 1.0.0 1.1.0] },
  { name: "pomodoro", summary: "A tomato timer that respects your focus and your bar space.",
    kinds: [ "bar-widget" ], versions: %w[1.0.0] },
  { name: "now-playing", summary: "MPRIS now-playing with scrubbing, artwork, and taste.",
    kinds: [ "bar-widget", "popout" ], versions: %w[0.5.0 0.6.0] }
]

SAMPLES.each do |sample|
  sample[:versions].each do |version|
    plugin = ryan.plugins.find_by(name: sample[:name])
    next if plugin&.version_burned?(version)

    manifest = {
      "schemaVersion" => 1,
      "id" => "ryanrhughes.#{sample[:name]}",
      "name" => sample[:name].titleize,
      "description" => sample[:summary],
      "version" => version,
      "kinds" => sample[:kinds],
      "entryPoints" => sample[:kinds].index_with { "Widget.qml" },
      "license" => "MIT",
      "repository" => "https://github.com/ryanrhughes/#{sample[:name]}"
    }
    readme = <<~MD
      # #{sample[:name].titleize}

      #{sample[:summary]}

      ## Install

      ```
      omarchy plugin add ryanrhughes/#{sample[:name]}
      ```

      ## Features

      - Zero configuration, sensible defaults
      - Follows your Omarchy theme
      - Tiny footprint
    MD
    bytes = build_tarball(manifest, { "Widget.qml" => "import QtQuick\nItem {}\n", "README.md" => readme })
    created = Registry::PublishVersion.new(user: admin, publisher: ryan, plugin_name: sample[:name], tarball_bytes: bytes).call
    Registry::ReviewJob.perform_now(created)
    puts "published ryanrhughes/#{sample[:name]}@#{version} (#{created.reload.state})"
  end
end

DataPlane::Regenerate.all
puts "Seeded. Admin: ryan@heyoodle.com (passwordless — request a code in dev, it shows in the flash)."
