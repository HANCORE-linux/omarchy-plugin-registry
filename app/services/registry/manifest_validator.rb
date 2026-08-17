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

    # The complete SPDX license list, vendored from spdx.org (config/spdx.json,
    # list version recorded inside) — real identifiers only, all of them.
    SPDX_DATA = JSON.parse(Rails.root.join("config/spdx.json").read).freeze
    SPDX_LICENSE_IDS = SPDX_DATA["licenses"].to_set.freeze
    SPDX_EXCEPTION_IDS = SPDX_DATA["exceptions"].to_set.freeze

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
      # Types are part of the contract — a numeric or object-valued field must
      # never reach a version row for clients to choke on
      %w[id name version license minOmarchyVersion repository author].each do |field|
        value = manifest[field]
        # nil-check, not present? — `false` and other non-strings must fail
        errors << "manifest #{field} must be a string" if !value.nil? && !value.is_a?(String)
      end
      name = manifest["name"]
      if name.is_a?(String) && (name.length > 80 || name.match?(/[[:cntrl:]]/))
        errors << "manifest name must be at most 80 printable characters"
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
      # Build metadata is ignored in semver precedence — 1.0.0+a and 1.0.0+b
      # would be "equal" versions with different bytes, which immutability
      # cannot allow
      errors << "version must not carry build metadata (+...)" if version.include?("+")
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

    # "MIT", "(MIT OR Apache-2.0)", "GPL-3.0-only WITH GCC-exception-3.1", …
    # Recursive-descent over the SPDX expression grammar:
    #   expr := term ((OR|AND) term)* ; term := ID [WITH EXC] | "(" expr ")"
    def valid_spdx_expression?(expression)
      parser = SpdxExpressionParser.new(expression)
      parser.valid?
    end

    class SpdxExpressionParser
      def initialize(expression)
        @tokens = expression.to_s.gsub("(", " ( ").gsub(")", " ) ").split(/\s+/).reject(&:empty?)
        @position = 0
      end

      def valid?
        return false if @tokens.empty?
        parse_expr && @position == @tokens.length
      end

      private

      def peek = @tokens[@position]
      def advance = @tokens[@position].tap { @position += 1 }

      def parse_expr
        return false unless parse_term
        while %w[OR AND].include?(peek)
          advance
          return false unless parse_term
        end
        true
      end

      def parse_term
        if peek == "("
          advance
          return false unless parse_expr
          return false unless peek == ")"
          advance
          true
        elsif SPDX_LICENSE_IDS.include?(peek)
          advance
          if peek == "WITH"
            advance
            return false unless SPDX_EXCEPTION_IDS.include?(peek)
            advance
          end
          true
        else
          false
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
