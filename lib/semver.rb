# Strict semantic versioning (semver.org 2.0.0) — parse, validate, compare.
# The registry requires every published version to be valid semver and strictly
# greater than the last published version of the plugin.
class Semver
  include Comparable

  PATTERN = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?\z/

  attr_reader :major, :minor, :patch, :prerelease, :build

  def self.valid?(string)
    string.is_a?(String) && PATTERN.match?(string)
  end

  def self.parse(string)
    match = PATTERN.match(string.to_s) or raise ArgumentError, "invalid semver: #{string.inspect}"
    new(match[1].to_i, match[2].to_i, match[3].to_i, match[4], match[5])
  end

  def initialize(major, minor, patch, prerelease = nil, build = nil)
    @major, @minor, @patch, @prerelease, @build = major, minor, patch, prerelease, build
  end

  def <=>(other)
    cmp = [ major, minor, patch ] <=> [ other.major, other.minor, other.patch ]
    return cmp unless cmp.zero?
    return 0 if prerelease == other.prerelease
    return 1 if prerelease.nil?   # release > any prerelease
    return -1 if other.prerelease.nil?
    compare_prereleases(prerelease.split("."), other.prerelease.split("."))
  end

  # Zero-padded key so lexicographic order matches semver order in SQL.
  # Prerelease ordering is approximated; exact comparison happens in Ruby.
  def sort_key
    key = format("%010d.%010d.%010d", major, minor, patch)
    prerelease ? "#{key}-#{prerelease}" : "#{key}~" # "~" sorts releases after prereleases
  end

  def to_s
    s = "#{major}.#{minor}.#{patch}"
    s += "-#{prerelease}" if prerelease
    s += "+#{build}" if build
    s
  end

  private

  def compare_prereleases(a, b)
    a.zip(b).each do |x, y|
      return 1 if y.nil?
      numeric_x, numeric_y = x.match?(/\A\d+\z/), y.match?(/\A\d+\z/)
      cmp =
        if numeric_x && numeric_y then x.to_i <=> y.to_i
        elsif numeric_x then -1    # numeric identifiers sort before alphanumeric
        elsif numeric_y then 1
        else x <=> y
        end
      return cmp unless cmp.zero?
    end
    a.length <=> b.length
  end
end
