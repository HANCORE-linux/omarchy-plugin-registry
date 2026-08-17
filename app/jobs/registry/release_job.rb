module Registry
  # Releases a version once its hold window has passed — unless review or an
  # admin changed its state in the meantime.
  class ReleaseJob < ApplicationJob
    queue_as :critical

    def perform(version)
      return unless version.held?
      return if version.hold_until&.future?
      ReleaseVersion.call(version)
    rescue ArgumentError => e
      # A duplicate job racing a successful release sees "cannot release a
      # published version" — that's success, not a problem to park.
      return if version.reload.published?
      return unless version.held?

      # Genuinely refused release (suspension, membership loss, plugin state
      # change): park it for a human instead of retry-crashing.
      version.update!(state: :quarantined, review_notes: "release blocked: #{e.message}")
      AuditEvent.record!(action: "version.release_blocked", subject: version,
        metadata: { plugin: version.plugin.full_name, version: version.version, reason: e.message })
    end
  end
end
