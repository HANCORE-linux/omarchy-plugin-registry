module Registry
  # The warning banners a plugin (or one of its versions) carries: security
  # holds, quarantines, revocations, yanks, and the publisher-only "not public
  # yet" notice. One definition feeds both the web page and the JSON a native
  # client renders — a takedown notice that appears on the site but not in the
  # in-desktop browser would be the worst possible drift.
  #
  # The chains are mutually exclusive by design (most severe wins), but the
  # result is a list so a caller never has to special-case zero-or-one.
  class PluginNotices
    Notice = Struct.new(:kind, :tone, :title, :body, keyword_init: true)

    MAX_LISTED_YANKS = 3

    def self.for_plugin(plugin:, versions:, privileged: false)
      new.plugin_notices(plugin:, versions:, privileged:)
    end

    # Version-page notices are limited to the drift-critical ones (withdrawn,
    # not-yet-cleared). "You are viewing an older version" stays presentation
    # chrome in the web view — a JSON client compares the version it fetched
    # against the plugin's latest_version itself.
    def self.for_version(version:)
      new.version_notices(version:)
    end

    def plugin_notices(plugin:, versions:, privileged:)
      if privileged && !plugin.ever_public? && !plugin.security_holding?
        [ Notice.new(kind: "not_public", tone: "warning", title: "Not public yet.",
            body: "Nothing here has cleared review, so this page is visible only to " \
                  "#{plugin.publisher.name} members and admins. It goes public the moment a version releases.") ]
      elsif plugin.security_holding?
        [ Notice.new(kind: "security_holding", tone: "danger", title: "Security holding.",
            body: "This plugin was removed for malware and its name is permanently retired. " \
                  "Every version is on the signed revocation list; clients disable installed copies when they next sync it.") ]
      elsif plugin.quarantined?
        [ Notice.new(kind: "quarantined", tone: "warning", title: "Under review.",
            body: "This plugin is quarantined while our team investigates. It cannot be installed right now.") ]
      elsif plugin.revocations.any?
        [ Notice.new(kind: "revoked", tone: "danger", title: "Security notice.",
            body: "One or more versions of this plugin are on the signed revocation list; " \
                  "clients disable affected installs when they next sync it.") ]
      elsif (withdrawn = versions.select(&:yanked?)).any?
        [ Notice.new(kind: "yanked_versions", tone: "warning", title: "Withdrawn versions.",
            body: withdrawn.first(MAX_LISTED_YANKS).map { |v| yank_sentence(v) }.join(" ")) ]
      else
        []
      end
    end

    def version_notices(version:)
      if version.yanked?
        [ Notice.new(kind: "yanked", tone: "warning", title: "Withdrawn.",
            body: "#{yank_sentence(version)} It no longer resolves for new installs.") ]
      elsif !version.published?
        [ Notice.new(kind: version.state, tone: "warning", title: "#{version.state.humanize}.",
            body: "This version has not cleared review — only publisher members and admins can see it.") ]
      else
        []
      end
    end

    private

    def yank_sentence(version)
      "v#{version.version} was yanked#{" — #{version.yank_reason}" if version.yank_reason.present?}."
    end
  end
end
