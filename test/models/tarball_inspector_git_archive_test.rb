require "test_helper"

class TarballInspectorGitArchiveTest < ActiveSupport::TestCase
  test "accepts a real git archive (PAX global header) end to end" do
    Dir.mktmpdir do |dir|
      system("git", "init", "-q", dir)
      File.write(File.join(dir, "manifest.json"), TarballBuilder::DEFAULT_MANIFEST.to_json)
      File.write(File.join(dir, "Widget.qml"), "import QtQuick\nItem {}\n")
      system("git", "-C", dir, "add", "-A", exception: true)
      system("git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "x", exception: true)
      bytes = IO.popen([ "git", "-C", dir, "archive", "--format=tar.gz", "HEAD" ], "rb", &:read)

      tarball = Registry::TarballInspector.inspect_bytes(bytes)
      assert_includes tarball.files, "manifest.json"
      assert_equal "acme.weather", tarball.manifest["id"]
    end
  end

  test "rejects concatenated gzip members" do
    smuggled = TarballBuilder.build + TarballBuilder.build(files: { "evil.sh" => "#!/bin/bash\n" })
    error = assert_raises(Registry::TarballInspector::InvalidTarball) do
      Registry::TarballInspector.inspect_bytes(smuggled)
    end
    assert_match(/trailing data/, error.message)
  end
end
