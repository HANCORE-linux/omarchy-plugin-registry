module Registry
  # Releases a version once its hold window has passed — unless review or an
  # admin changed its state in the meantime.
  class ReleaseJob < ApplicationJob
    queue_as :default

    def perform(version)
      return unless version.held?
      return if version.hold_until&.future?
      ReleaseVersion.call(version)
    end
  end
end
