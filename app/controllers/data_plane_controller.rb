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
    count_download(version)
    serve("dl/#{params[:publisher]}/#{params[:plugin]}/#{filename}",
      type: "application/gzip", disposition: "attachment", filename: filename)
  end

  private

  # ?sig=1 (or .sig-suffixed routes) serve the detached signature instead
  def sig_suffix = params[:sig].present? ? ".sig" : ""

  def content_type_for_json = params[:sig].present? ? "text/plain" : "application/json"

  def serve(relative_path, type:, disposition: "inline", filename: nil)
    path = DataPlane.root.join(relative_path)
    return head :not_found unless path.file? && path.to_s.start_with?(DataPlane.root.to_s)
    response.headers["Cache-Control"] = "public, max-age=60"
    send_file path, type:, disposition:, filename:
  end

  def count_download(version_string)
    version = PluginVersion.joins(plugin: :publisher).find_by(
      plugins: { name: params[:plugin] }, publishers: { name: params[:publisher] },
      version: version_string
    )
    DailyDownload.record!(version) if version
  end
end
