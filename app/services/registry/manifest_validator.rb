module Registry
  # Server-side mirror of omarchy-plugin-validate plus registry-only rules.
  # All registry metadata derives from the manifest inside the tarball — no
  # sidecar metadata is accepted (kills the manifest-confusion bug class).
  #
  # TODO: sync ALLOWED_KINDS and the kind/entry-point table verbatim with
  # bin/omarchy-plugin-validate from the Quattro repo before launch.
  class ManifestValidator
    ALLOWED_KINDS = %w[bar-widget panel popout service command theme].freeze
    ID_FORMAT = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
    SPDX_FORMAT = /\A[A-Za-z0-9.+\-]+(?:\s(?:OR|AND|WITH)\s[A-Za-z0-9.+\-]+)*\z/

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

    def check_kinds
      kinds = manifest["kinds"]
      return errors << "kinds must be a non-empty array" unless kinds.is_a?(Array) && kinds.any?
      unknown = kinds - ALLOWED_KINDS
      errors << "unknown kinds: #{unknown.join(', ')}" if unknown.any?
    end

    def check_entry_points
      entry_points = manifest["entryPoints"]
      return errors << "entryPoints must be an object" unless entry_points.is_a?(Hash)
      entry_points.each do |kind, path|
        unless path.is_a?(String) && !path.start_with?("/") && !path.split("/").include?("..")
          errors << "entry point for #{kind} must be a relative path inside the plugin"
          next
        end
        errors << "entry point #{path} not found in tarball" unless tarball.include?(path)
      end
    end

    def check_license
      license = manifest["license"].to_s
      return errors << "license is required to publish (SPDX identifier)" if license.blank?
      errors << "license must be an SPDX expression (got #{license})" unless license.match?(SPDX_FORMAT)
    end
  end
end
