module DataPlane
  class RegenerateJob < ApplicationJob
    queue_as :default

    def perform(plugin = nil)
      plugin ? Regenerate.plugin(plugin) : Regenerate.all
    end
  end
end
