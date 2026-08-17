module Registry
  # Server-side mirror of omarchy-plugin-validate plus registry-only rules.
  # All registry metadata derives from the manifest inside the tarball — no
  # sidecar metadata is accepted (kills the manifest-confusion bug class).
  #
  # KIND_ENTRY_RULES is the registry's authoritative kind/entry-point contract;
  # the Quattro-side validator must stay in lockstep (tracked in docs/client-spec.md).
  class ManifestValidator
    # kind => allowed entry-point extensions
    KIND_ENTRY_RULES = {
      "bar-widget" => %w[.qml],
      "panel" => %w[.qml],
      "popout" => %w[.qml],
      "service" => %w[.qml .sh],
      "command" => %w[.sh],
      "theme" => %w[.json .css]
    }.freeze
    ALLOWED_KINDS = KIND_ENTRY_RULES.keys.freeze
    ID_FORMAT = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/

    # Real SPDX identifiers only — token-shaped inventions must not become
    # trusted registry metadata. (The common set; extend as publishers need.)
    SPDX_LICENSE_IDS = %w[
      0BSD AGPL-3.0-only AGPL-3.0-or-later Apache-2.0 Artistic-2.0 BSD-2-Clause
      BSD-3-Clause BSD-3-Clause-Clear BlueOak-1.0.0 BSL-1.0 CC-BY-4.0 CC-BY-SA-4.0
      CC0-1.0 CDDL-1.0 EPL-1.0 EPL-2.0 EUPL-1.2 GPL-2.0-only GPL-2.0-or-later
      GPL-3.0-only GPL-3.0-or-later ISC LGPL-2.1-only LGPL-2.1-or-later
      LGPL-3.0-only LGPL-3.0-or-later MIT MIT-0 MPL-2.0 MulanPSL-2.0 NCSA
      OFL-1.1 OSL-3.0 PostgreSQL Unlicense UPL-1.0 WTFPL Zlib
    ].to_set.freeze
    SPDX_EXCEPTION_FORMAT = /\A[A-Za-z0-9.\-]+-exception(-[A-Za-z0-9.\-]+)?\z/i

    attr_reader :errors

    def initialize(manifest:, publisher:, plugin_name:, tarball:)
      @manifest = manifest
      @publisher = publisher
      @plugin_name = plugin_name
      @tarball = tarball
      @errors = []
    end

    def valid?
      check_schema_version
      check_required_fields
      check_id
      check_version
      check_kinds
      check_entry_points
      check_license
      check_repository
      check_min_omarchy_version
      errors.empty?
    end

    private

    attr_reader :manifest, :publisher, :plugin_name, :tarball

    def check_schema_version
      errors << "schemaVersion must be 1" unless manifest["schemaVersion"] == 1
    end

    def check_required_fields
      %w[id name version kinds entryPoints].each do |field|
        errors << "manifest missing required field: #{field}" if manifest[field].blank?
      end
    end

    def check_id
      id = manifest["id"].to_s
      return if id.blank?
      errors << "manifest id has illegal characters" unless id.match?(ID_FORMAT)
      expected = "#{publisher.name}.#{plugin_name}"
      errors << "manifest id must be #{expected} (got #{id})" unless id == expected
    end

    def check_version
      version = manifest["version"].to_s
      return if version.blank?
      errors << "version must be strict semver (got #{version})" unless Semver.valid?(version)
    end

    # Part of the signed compatibility contract — clients resolve against it,
    # so malformed values must never reach the index.
    def check_min_omarchy_version
      min = manifest["minOmarchyVersion"]
      return if min.nil?
      unless min.is_a?(String) && Semver.valid?(min)
        errors << "minOmarchyVersion must be a strict semver string (got #{min.inspect})"
      end
    end

    def check_kinds
      kinds = manifest["kinds"]
      unless kinds.is_a?(Array) && kinds.any? && kinds.all? { |k| k.is_a?(String) }
        return errors << "kinds must be a non-empty array of strings"
      end
      unknown = kinds - ALLOWED_KINDS
      errors << "unknown kinds: #{unknown.join(', ')}" if unknown.any?
    end

    def check_entry_points
      entry_points = manifest["entryPoints"]
      return errors << "entryPoints must be an object" unless entry_points.is_a?(Hash)

      kinds = Array(manifest["kinds"])
      if kinds.any? && kinds.all? { |k| k.is_a?(String) } && entry_points.keys.sort != kinds.sort
        errors << "entryPoints keys must exactly match kinds (kinds: #{kinds.sort.join(', ')}; entryPoints: #{entry_points.keys.sort.join(', ')})"
      end

      entry_points.each do |kind, path|
        unless path.is_a?(String) && !path.start_with?("/") && !path.split("/").include?("..")
          errors << "entry point for #{kind} must be a relative path inside the plugin"
          next
        end
        errors << "entry point #{path} not found in tarball" unless tarball.include?(path)

        allowed = KIND_ENTRY_RULES[kind]
        if allowed && allowed.exclude?(File.extname(path).downcase)
          errors << "entry point for #{kind} must be #{allowed.join(' or ')} (got #{path})"
        end
      end
    end

    def check_license
      license = manifest["license"].to_s
      return errors << "license is required to publish (SPDX identifier)" if license.blank?
      errors << "license must be a known SPDX expression (got #{license})" unless valid_spdx_expression?(license)
    end

    # "MIT", "MIT OR Apache-2.0", "GPL-3.0-only WITH GCC-exception-3.1", …
    # Token sequence must alternate id, operator, id, … with known ids.
    def valid_spdx_expression?(expression)
      tokens = expression.split(/\s+/)
      return false if tokens.empty? || tokens.length.even?

      tokens.each_with_index.all? do |token, index|
        if index.odd?
          %w[OR AND WITH].include?(token)
        elsif index.positive? && tokens[index - 1] == "WITH"
          token.match?(SPDX_EXCEPTION_FORMAT)
        else
          SPDX_LICENSE_IDS.include?(token)
        end
      end
    end

    # Rendered as a link on the plugin page — https only, sane length.
    def check_repository
      repository = manifest["repository"]
      return if repository.blank?
      uri = URI.parse(repository.to_s) rescue nil
      unless uri.is_a?(URI::HTTPS) && repository.to_s.length <= 300
        errors << "repository must be an https:// URL"
      end
    end
  end
end
