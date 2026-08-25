class AllowBroaderApiTokenScope < ActiveRecord::Migration[8.1]
  # Account-wide by default (matches RubyGems/npm): a null publisher_id means
  # "any namespace the user belongs to", a null plugin_name means "any plugin
  # in that publisher". Non-null values still narrow the scope (trusted
  # publishing keeps minting per-plugin tokens).
  def change
    change_column_null :api_tokens, :publisher_id, true
    change_column_null :api_tokens, :plugin_name, true
  end
end
