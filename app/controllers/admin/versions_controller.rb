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
        # Full-content digests, never the truncated scan window — same-prefix
        # files with different tails must show as changed
        @changed_files = (@tarball&.files || []).select do |f|
          previous_tarball.digests.key?(f) && previous_tarball.digests[f] != @tarball.digests[f]
        end
      end
    end

    def download_tarball
      return head :not_found unless @version.tarball.attached?
      send_data @version.tarball.download, filename: @version.tarball_filename,
        type: "application/gzip", disposition: "attachment"
    end

    # Approve out of QUARANTINE only — held versions are clean and waiting out
    # the publish-delay window, which an admin click must not bypass; they
    # release themselves when the hold expires.
    def approve
      return bad_transition! unless @version.quarantined?
      Registry::ReleaseVersion.call(@version, actor: Current.user)
      audit "version.approve"
      regenerate_and_redirect "Approved and published."
    rescue ArgumentError => e
      redirect_to admin_root_path, alert: e.message
    end

    # Legal admin transitions only: rejected/yanked are terminal for these
    # actions, and quarantine applies to live versions.
    def reject
      return bad_transition! unless @version.releasable? || @version.processing?
      return require_reason! unless params[:reason].present?
      @version.update!(state: :rejected, review_notes: params[:reason])
      @version.plugin.refresh_latest_version!
      audit "version.reject", public: true, metadata: { reason: params[:reason] }
      regenerate_and_redirect "Rejected — version number stays burned."
    end

    def quarantine
      return bad_transition! unless @version.published?
      return require_reason! unless params[:reason].present?
      @version.update!(state: :quarantined, review_notes: params[:reason])
      @version.plugin.refresh_latest_version!
      audit "version.quarantine", public: true, metadata: { reason: params[:reason] }
      regenerate_and_redirect "Quarantined — drops from the index on regen."
    end

    def yank
      return bad_transition! unless @version.published?
      return require_reason! unless params[:reason].present?
      @version.yank!(reason: params[:reason], actor: Current.user)
      regenerate_and_redirect "Yanked."
    end

    # The kill-bit: yank + revocation entry reaching already-installed copies.
    def revoke
      return bad_transition! unless @version.published? || @version.yanked? || @version.quarantined?
      return require_reason! unless params[:reason].present?
      reason = params[:reason]
      ApplicationRecord.transaction do
        if @version.published?
          @version.yank!(reason:, actor: Current.user)
        else
          # Revocation is terminal from any state: a revoked version must
          # never be approvable back into the index
          @version.update!(state: :yanked, yanked_at: Time.current, yank_reason: reason)
        end
        Revocation.find_or_create_by!(plugin: @version.plugin, version: @version.version) do |r|
          r.reason = reason
          r.created_by = Current.user
        end
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

    def require_reason!
      redirect_to admin_version_path(@version), alert: "A public reason is required for takedown actions."
    end

    def bad_transition!
      redirect_to admin_version_path(@version), alert: "That action isn't valid from the #{@version.state} state."
    end

    def regenerate_and_redirect(notice)
      DataPlane::RegenerateJob.perform_later(@version.plugin)
      redirect_to admin_root_path, notice: notice
    end
  end
end
