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
