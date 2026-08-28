json.schema_version 1

json.publisher do
  json.partial! "publishers/publisher", publisher: @publisher
  json.plugin_count @plugins.size
end

json.plugins @plugins do |plugin|
  json.partial! "plugins/plugin", plugin: plugin
end
