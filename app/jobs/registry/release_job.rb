module Registry
  # Releases a version once its hold window has passed — unless review or an
  # admin changed its state in the meantime.
  class ReleaseJob < ApplicationJob
    queue_as :default

    def perform(version)
      return unless version.held?
      return if version.hold_until&.future?
      ReleaseVersion.call(version)
    rescue ArgumentError => e
      # Refused release (suspension, membership loss, plugin state change):
      # park it for a human instead of retry-crashing.
      version.update!(state: :quarantined, review_notes: "release blocked: #{e.message}")
      AuditEvent.record!(action: "version.release_blocked", subject: version,
        metadata: { plugin: version.plugin.full_name, version: version.version, reason: e.message })
    end
  end
end
