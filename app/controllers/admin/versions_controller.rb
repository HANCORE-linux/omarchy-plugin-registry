module Admin
  class VersionsController < BaseController
    before_action :set_version

    # Approve out of quarantine/hold — releases through the same path as the
    # automated pipeline so frozen bytes and audit stay consistent.
    def approve
      Registry::ReleaseVersion.call(@version, actor: Current.user)
      audit "version.approve"
      regenerate_and_redirect "Approved and published."
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
