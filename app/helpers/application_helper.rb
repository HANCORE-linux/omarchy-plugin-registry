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
