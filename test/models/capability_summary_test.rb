require "test_helper"

class CapabilitySummaryTest < ActiveSupport::TestCase
  test "an inert fingerprint is empty rather than a grid of blanks" do
    summary = Registry::CapabilitySummary.new(
      "processes" => [], "network" => [], "paths" => [], "writes" => [],
      "keybindings" => false, "shell_digests" => [],
      "dynamic_paths" => [], "dynamic_exec" => [], "dynamic_network" => [])
    assert summary.empty?
    assert_equal [], summary.rows
  end

  test "drops growth-bookkeeping digests but keeps human-readable entries" do
    summary = Registry::CapabilitySummary.new(
      "processes" => [ "argv:1a2b3c4d5e6f", "bash", "bash -c #a1b2c3d4", "cmd:a1b2c3d4e5f6", "curl" ],
      "network" => [ "api.github.com" ],
      "paths" => [ "/usr/share/omarchy", "overflow:abcdef123456 (350 total)" ])
    runs = summary.rows.find { |r| r.label == "Runs" }
    assert_equal %w[bash curl], runs.items
    assert_equal [ "api.github.com" ], summary.rows.find { |r| r.label == "Connects to" }.items
    assert_equal [ "/usr/share/omarchy" ], summary.rows.find { |r| r.label == "Accesses" }.items
  end

  test "flag tokens and bare numbers never read as commands" do
    summary = Registry::CapabilitySummary.new("processes" => [ "-", "--cacert", "-v", "7.5", "curl" ])
    assert_equal [ "curl" ], summary.rows.find { |r| r.label == "Runs" }.items
  end

  test "large command lists stay fully visible with binary-shaped names first" do
    summary = Registry::CapabilitySummary.new(
      "processes" => [ "Deliberately", "curl", "self.axes", "omarchy-toggle", "jq", "EXIT_USAGE" ])
    row = summary.rows.find { |r| r.label == "Runs" }
    assert_equal [ "omarchy-toggle", "curl", "jq", "Deliberately", "EXIT_USAGE", "self.axes" ], row.items
  end

  test "executed files show as filenames without content digests" do
    summary = Registry::CapabilitySummary.new("shell_digests" => [ "scripts/service.sh#a1b2c3d4e5f6" ])
    assert_equal [ "scripts/service.sh" ], summary.rows.find { |r| r.label == "Executes" }.items
  end

  test "keybindings boolean becomes a row only when true" do
    on = Registry::CapabilitySummary.new("keybindings" => true)
    assert_equal [ "keyboard shortcuts" ], on.rows.find { |r| r.label == "Registers" }.items
    off = Registry::CapabilitySummary.new("keybindings" => false)
    assert off.empty?
  end

  test "dynamic dimensions collapse to call-site counts" do
    summary = Registry::CapabilitySummary.new(
      "dynamic_exec" => [ "1a2b3c4d5e6f", "2b3c4d5e6f7a" ],
      "dynamic_network" => [ "3c4d5e6f7a8b" ])
    row = summary.rows.find { |r| r.label == "Computed at runtime" }
    assert_equal [ "commands — 2 call sites",
                   "network destinations — 1 call site" ], row.items
    assert_not row.code?
  end

  test "capped dynamic lists report the true total from the overflow marker" do
    entries = Array.new(200) { |i| format("%012x", i) } + [ "overflow:abcdef123456 (350 total)" ]
    summary = Registry::CapabilitySummary.new("dynamic_paths" => entries)
    assert_equal [ "file paths — 350 call sites" ],
      summary.rows.find { |r| r.label == "Computed at runtime" }.items
  end

  test "rows preview a handful of items and expose the rest" do
    summary = Registry::CapabilitySummary.new("paths" => Array.new(10) { |i| "/etc/thing#{i}" })
    row = summary.rows.find { |r| r.label == "Accesses" }
    assert_equal 6, row.preview.size
    assert_equal 4, row.hidden.size
  end

  test "legacy boolean fingerprints for dynamic dimensions do not raise" do
    summary = Registry::CapabilitySummary.new("dynamic_exec" => true)
    row = summary.rows.find { |r| r.label == "Computed at runtime" }
    assert_equal [ "commands — 1 call site" ], row.items
  end
end
