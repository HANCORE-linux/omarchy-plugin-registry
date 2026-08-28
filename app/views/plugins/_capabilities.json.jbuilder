# The privacy-label read of the capability fingerprint — the same
# Registry::CapabilitySummary the web page renders, so a native install
# confirmation shows exactly what the site shows. `empty` true is the
# strongest claim the registry can make, not missing data.
summary = Registry::CapabilitySummary.new(version.capability_fingerprint)
json.empty summary.empty?
json.rows summary.rows do |row|
  json.label row.label
  json.code row.code?
  json.items row.items
end
