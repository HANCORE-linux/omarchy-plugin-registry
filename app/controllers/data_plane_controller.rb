# Serves the static data plane in development and as origin behind the CDN in
# production. Installs read these paths; nothing here touches the database
# except the download counter (which CDN log aggregation replaces at scale).
class DataPlaneController < ActionController::API
  def config = serve("config.json#{sig_suffix}", type: content_type_for_json)
  def all = serve("all.json#{sig_suffix}", type: content_type_for_json)
  def revocations = serve("revocations.json#{sig_suffix}", type: content_type_for_json)
  def signing_key = serve("signing-key.pub", type: "text/plain")

  def index_file
    serve("index/#{params[:publisher]}/#{params[:plugin]}.json#{sig_suffix}", type: content_type_for_json)
  end

  def tarball
    filename = params[:plugin_file]
    version = filename[/\A#{Regexp.escape(params[:plugin])}-(.+)\.tar\.gz\z/, 1]
    return head :not_found unless version
    served = serve("dl/#{params[:publisher]}/#{params[:plugin]}/#{filename}",
      type: "application/gzip", disposition: "attachment", filename: filename,
      cache_control: "public, max-age=31536000, immutable")
    # Origin counting is a dev/small-scale convenience; production counts come
    # from CDN log aggregation (config disables the synchronous DB writes an
    # anonymous GET could otherwise hammer).
    count_download(version) if served && Rails.application.config.x.count_origin_downloads
  end

  private

  # ?sig=1 (or .sig-suffixed routes) serve the detached signature instead
  def sig_suffix = params[:sig].present? ? ".sig" : ""

  def content_type_for_json = params[:sig].present? ? "text/plain" : "application/json"

  # Returns truthy only when the file was actually sent. Indexes are mutable
  # (short cache); immutable tarballs pass their own cache_control.
  def serve(relative_path, type:, disposition: "inline", filename: nil, cache_control: "public, max-age=60")
    path = DataPlane.root.join(relative_path)
    unless path.file? && path.to_s.start_with?(DataPlane.root.to_s)
      head :not_found
      return false
    end
    response.headers["Cache-Control"] = cache_control
    send_file(path, type: type, disposition: disposition, filename: filename)
    true
  end

  def count_download(version_string)
    version = PluginVersion.published.joins(plugin: :publisher).find_by(
      plugins: { name: params[:plugin] }, publishers: { name: params[:publisher] },
      version: version_string
    )
    DailyDownload.record!(version) if version
  end
end
