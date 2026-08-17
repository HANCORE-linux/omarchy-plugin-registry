module DataPlane
  class RegenerateJob < ApplicationJob
    queue_as :critical
    # One regeneration at a time — concurrent regens could interleave files
    # from different generations across the index.
    limits_concurrency to: 1, key: "data_plane_regenerate"

    def perform(plugin = nil)
      plugin ? Regenerate.plugin(plugin) : Regenerate.all
    end
  end
end
