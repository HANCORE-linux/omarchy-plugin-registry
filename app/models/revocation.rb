# Kill-list entry. Serialized into revocations.json on the data plane; clients
# check it on add, on update, and periodically, and disable matching installed
# plugins. version nil revokes every version of the plugin.
class Revocation < ApplicationRecord
  belongs_to :plugin
  belongs_to :created_by, class_name: "User"

  validates :reason, presence: true
  validates :version, uniqueness: { scope: :plugin_id }

  def as_kill_list_entry
    { "plugin" => plugin.manifest_id, "version" => version, "reason" => reason,
      "revoked_at" => created_at.utc.iso8601 }.compact
  end
end
