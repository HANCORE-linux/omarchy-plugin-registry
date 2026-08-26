module ApplicationHelper
  def render_markdown(text)
    return "" if text.blank?
    Commonmarker.to_html(text,
      options: { extension: { table: true, strikethrough: true, autolink: true, tasklist: true },
                 render: { unsafe: false } }).html_safe
  end

  def compact_number(number)
    number_to_human(number, format: "%n%u", precision: 3, significant: true,
      units: { thousand: "k", million: "M", billion: "B" }, strip_insignificant_zeros: true)
  end

  # Turns a manifest-provided repository URL into { icon:, label:, url: } for the
  # sidebar Source row, or nil when the value isn't a linkable http(s) URL.
  def source_repo(url)
    uri = URI.parse(url.to_s)
    return nil unless uri.is_a?(URI::HTTP) && uri.host.present?
    host = uri.host.downcase.delete_prefix("www.")
    icon, label =
      case host
      when "github.com" then [ :github, "GitHub" ]
      when "gitlab.com" then [ :gitlab, "GitLab" ]
      when /\Agitlab\./ then [ :gitlab, host ]
      when "codeberg.org" then [ :link, "Codeberg" ]
      when "bitbucket.org" then [ :link, "Bitbucket" ]
      else [ :link, host ]
      end
    { icon: icon, label: label, url: uri.to_s }
  rescue URI::InvalidURIError
    nil
  end

  DEFAULT_META_DESCRIPTION = "The Omarchy plugin registry — hosted, scanned, revocable. Browse, install, and publish plugins for Omarchy.".freeze

  # OpenGraph/Twitter tags with absolute URLs. Pages call this through
  # content_for(:social); the layout falls back to the site-wide card.
  def social_meta(title:, description:, image_path:, url_path:)
    base = DataPlane.base_url
    safe_join([
      tag.meta(property: "og:type", content: "website"),
      tag.meta(property: "og:site_name", content: "Omarchy Plugins"),
      tag.meta(property: "og:title", content: title),
      tag.meta(property: "og:description", content: description),
      tag.meta(property: "og:url", content: "#{base}#{url_path}"),
      tag.meta(property: "og:image", content: "#{base}#{image_path}"),
      tag.meta(property: "og:image:width", content: 1200),
      tag.meta(property: "og:image:height", content: 630),
      tag.meta(name: "twitter:card", content: "summary_large_image"),
      tag.meta(name: "twitter:title", content: title),
      tag.meta(name: "twitter:description", content: description)
    ], "\n")
  end

  # Directory links that keep the current search/sort/filter state — pass only
  # what changes. Page deliberately resets unless overridden: a filter change
  # always lands on its own first page.
  def directory_path(overrides = {})
    root_path({ q: @query.presence, sort: (@sort if @sort != "downloads"),
                category: @category, tag: @tag }.merge(overrides).compact)
  end

  CARD_RECENCY = 14.days

  # "New" for a first release, "Updated" for a fresh version of an existing
  # plugin — driven by the first/last_published_at columns the directory query
  # selects alongside the row.
  def card_activity_badge(plugin)
    first = plugin.try(:first_published_at)
    return if first.blank?
    if Time.zone.parse(first.to_s) > CARD_RECENCY.ago
      tag.span "New", class: "badge badge--ok"
    elsif (last = plugin.try(:last_published_at)).present? && Time.zone.parse(last.to_s) > CARD_RECENCY.ago
      tag.span "Updated", class: "badge"
    end
  end

  def state_badge(state)
    tone = case state.to_s
    when "published", "active" then "badge--ok"
    when "yanked", "rejected", "security_holding" then "badge--danger"
    when "quarantined", "held" then "badge--warning"
    else ""
    end
    tag.span state.to_s.humanize, class: "badge #{tone}"
  end
end
