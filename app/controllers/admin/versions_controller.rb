module Admin
  class VersionsController < BaseController
    before_action :set_version

    # The inspection view behind every approval: exact bytes, full findings,
    # capability delta, file listing, and a diff of files vs the previous release.
    def show
      @plugin = @version.plugin
      @tarball = Registry::TarballInspector.inspect_bytes(@version.tarball.download) if @version.tarball.attached?
      previous = @plugin.versions.where(state: [ :published, :yanked ]).where.not(id: @version.id)
        .order(version_sort_key: :desc).first
      if previous&.tarball&.attached?
        @previous = previous
        previous_tarball = Registry::TarballInspector.inspect_bytes(previous.tarball.download)
        @added_files = (@tarball&.files || []) - previous_tarball.files
        @removed_files = previous_tarball.files - (@tarball&.files || [])
        @changed_files = (@tarball&.files || []).select do |f|
          previous_tarball.contents.key?(f) && previous_tarball.contents[f] != @tarball.contents[f]
        end
      end
    end

    def download_tarball
      return head :not_found unless @version.tarball.attached?
      send_data @version.tarball.download, filename: @version.tarball_filename,
        type: "application/gzip", disposition: "attachment"
    end

    # Approve out of quarantine/hold — releases through the same path as the
    # automated pipeline so frozen bytes and audit stay consistent.
    def approve
      Registry::ReleaseVersion.call(@version, actor: Current.user)
      audit "version.approve"
      regenerate_and_redirect "Approved and published."
    rescue ArgumentError => e
      redirect_to admin_root_path, alert: e.message
    end

    def reject
      @version.update!(state: :rejected, review_notes: params[:reason])
      @version.plugin.refresh_latest_version!
      audit "version.reject", public: true
      regenerate_and_redirect "Rejected — version number stays burned."
    end

    def quarantine
      @version.update!(state: :quarantined, review_notes: params[:reason])
      @version.plugin.refresh_latest_version!
      audit "version.quarantine", public: true
      regenerate_and_redirect "Quarantined — drops from the index on regen."
    end

    def yank
      @version.yank!(reason: params[:reason].presence || "yanked by admin", actor: Current.user)
      regenerate_and_redirect "Yanked."
    end

    # The kill-bit: yank + revocation entry reaching already-installed copies.
    def revoke
      reason = params[:reason].presence || "security"
      ApplicationRecord.transaction do
        @version.yank!(reason:, actor: Current.user) unless @version.yanked?
        Revocation.create!(plugin: @version.plugin, version: @version.version,
          reason:, created_by: Current.user)
        audit "version.revoke", public: true, metadata: { reason: }
      end
      regenerate_and_redirect "Revoked — kill list updated, installed copies will disable."
    end

    private

    def set_version
      @version = PluginVersion.find(params[:id])
    end

    def audit(action, public: false, metadata: {})
      AuditEvent.record!(actor: Current.user, action:, subject: @version, public:,
        metadata: { plugin: @version.plugin.full_name, version: @version.version }.merge(metadata))
    end

    def regenerate_and_redirect(notice)
      DataPlane::RegenerateJob.perform_later(@version.plugin)
      redirect_to admin_root_path, notice: notice
    end
  end
end
