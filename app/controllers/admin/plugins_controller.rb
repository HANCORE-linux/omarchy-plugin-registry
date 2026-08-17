module Admin
  class PluginsController < BaseController
    before_action :set_plugin

    # Nuclear option after confirmed malware: burn the name, revoke everything.
    def security_hold
      reason = params[:reason].presence || "malware"
      ApplicationRecord.transaction do
        @plugin.update!(state: :security_holding, latest_version: nil)
        @plugin.versions.published.find_each { |v| v.yank!(reason:, actor: Current.user) }
        # In-flight versions must not resurface via a scheduled ReleaseJob.
        # Anything that ever shipped stays in the signed index as yanked
        # (security notice preserved); never-published work is rejected.
        @plugin.versions.where(state: [ :processing, :held, :quarantined ]).where.not(published_at: nil)
          .update_all(state: PluginVersion.states[:yanked], yanked_at: Time.current, yank_reason: reason)
        @plugin.versions.where(state: [ :processing, :held, :quarantined ], published_at: nil)
          .update_all(state: PluginVersion.states[:rejected], review_notes: "plugin security-held: #{reason}")
        Revocation.find_or_create_by!(plugin: @plugin, version: nil) do |r|
          r.reason = reason
          r.created_by = Current.user
        end
        AuditEvent.record!(actor: Current.user, action: "plugin.security_hold", subject: @plugin,
          public: true, metadata: { plugin: @plugin.full_name, reason: })
      end
      DataPlane::RegenerateJob.perform_later(@plugin)
      redirect_to admin_root_path, notice: "#{@plugin.full_name} is now security-held; name burned, kill list updated."
    end

    private

    def set_plugin
      @plugin = Plugin.find(params[:id])
    end
  end
end
