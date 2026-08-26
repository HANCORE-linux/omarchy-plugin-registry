module Registry
  # Regenerates a plugin's preview renditions from whatever version is NOW the
  # latest published one. Enqueued whenever that changes (release, yank,
  # takedown); everything is re-derived from current state, so a stale or
  # duplicate run converges on the same result.
  class RefreshPreviewJob < ApplicationJob
    queue_as :review
    # Serialized per plugin: two racing runs could interleave purge/attach and
    # leave a card without its detail image.
    limits_concurrency to: 1, key: ->(plugin) { "preview_plugin_#{plugin.id}" }

    def perform(plugin)
      latest = plugin.active? ? plugin.latest_published_version : nil
      return clear!(plugin) if latest.nil? || !latest.tarball.attached?

      tarball = TarballInspector.inspect_bytes(latest.tarball.download)
      return clear!(plugin) if tarball.preview_bytes.nil?

      renditions = PreviewImage.process(tarball.preview_bytes, name: tarball.preview_name)
      plugin.preview_card.attach(
        io: StringIO.new(renditions[:card]), filename: "#{plugin.name}-card.webp", content_type: "image/webp")
      plugin.preview_detail.attach(
        io: StringIO.new(renditions[:detail]), filename: "#{plugin.name}-detail.webp", content_type: "image/webp")
      plugin.update!(preview_meta: renditions[:meta])
    rescue TarballInspector::InvalidTarball, PreviewImage::InvalidPreview
      # Historic tarball unreadable or preview no longer processable — cosmetic
      # only, never worth failing the job (and never worth keeping a preview
      # that belongs to a different version).
      clear!(plugin)
    end

    private

    def clear!(plugin)
      plugin.preview_card.purge if plugin.preview_card.attached?
      plugin.preview_detail.purge if plugin.preview_detail.attached?
      plugin.update!(preview_meta: {}) if plugin.preview_meta.present?
    end
  end
end
