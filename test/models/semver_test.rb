require "test_helper"

class SemverTest < ActiveSupport::TestCase
  test "validates strict semver" do
    assert Semver.valid?("1.0.0")
    assert Semver.valid?("0.1.0-rc.1")
    assert Semver.valid?("1.2.3+build.5")
    assert_not Semver.valid?("1.0")
    assert_not Semver.valid?("v1.0.0")
    assert_not Semver.valid?("01.0.0")
    assert_not Semver.valid?("1.0.0 ")
  end

  test "orders numerically, not lexically" do
    assert Semver.parse("0.10.0") > Semver.parse("0.9.9")
    assert Semver.parse("10.0.0") > Semver.parse("9.99.99")
  end

  test "prereleases sort before releases" do
    assert Semver.parse("1.0.0-rc.1") < Semver.parse("1.0.0")
    assert Semver.parse("1.0.0-alpha") < Semver.parse("1.0.0-alpha.1")
    assert Semver.parse("1.0.0-alpha.1") < Semver.parse("1.0.0-beta")
    assert Semver.parse("1.0.0-2") < Semver.parse("1.0.0-10")
    assert Semver.parse("1.0.0-1") < Semver.parse("1.0.0-alpha")
  end

  test "sort_key matches semver order for releases" do
    versions = %w[0.9.0 0.10.0 1.0.0 1.2.0 10.0.0]
    keys = versions.map { |v| Semver.parse(v).sort_key }
    assert_equal keys.sort, keys
  end

  test "sort_key puts prereleases before their release" do
    assert Semver.parse("1.0.0-rc.1").sort_key < Semver.parse("1.0.0").sort_key
  end

  test "sort_key orders numeric prerelease identifiers numerically" do
    assert Semver.parse("1.0.0-alpha.2").sort_key < Semver.parse("1.0.0-alpha.10").sort_key
    assert Semver.parse("1.0.0-2").sort_key < Semver.parse("1.0.0-10").sort_key
    assert Semver.parse("1.0.0-1").sort_key < Semver.parse("1.0.0-alpha").sort_key
    assert Semver.parse("1.0.0-alpha").sort_key < Semver.parse("1.0.0-alpha.1").sort_key
  end
end
