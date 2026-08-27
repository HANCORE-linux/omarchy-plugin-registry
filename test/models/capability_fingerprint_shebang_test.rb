require "test_helper"

class CapabilityFingerprintShebangTest < ActiveSupport::TestCase
  FakeTarball = Struct.new(:contents) do
    def files = contents.keys
  end

  def fingerprint(files)
    Registry::CapabilityFingerprint.compute(FakeTarball.new(files))
  end

  test "non-shell scripts record their interpreter, not tokenized source" do
    f = fingerprint("bin/daemon" => <<~PY)
      #!/usr/bin/env python3
      import os
      class Wheel:
          def spin(self):
              self.axes = []
    PY
    assert_includes f["processes"], "python3"
    assert_not_includes f["processes"], "import"
    assert_not_includes f["processes"], "class"
    assert_not_includes f["processes"], "self.axes"
    assert_equal 1, f["shell_digests"].size, "content still digest-tracked for growth"
  end

  test "extensionless shell shebang files tokenize exactly as before" do
    f = fingerprint("bin/helper" => "#!/bin/bash\ncurl -s https://example.com | jq .x\n")
    assert_includes f["processes"], "curl"
    assert_includes f["processes"], "jq"
    assert_not_includes f["processes"], "bash", "no new interpreter entry for shell scripts"
  end

  test "literal urls and paths in non-shell scripts are still captured" do
    f = fingerprint("bin/daemon" => <<~PY)
      #!/usr/bin/env python3
      URL = "https://api.example.com/v1"
      SOCKET = "/run/user/wheel.sock"
    PY
    assert_includes f["network"], "api.example.com"
    assert_includes f["paths"], "/run/user/wheel.sock"
  end
end
