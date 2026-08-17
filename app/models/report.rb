class Report < ApplicationRecord
  belongs_to :user
  belongs_to :reportable, polymorphic: true
  belongs_to :resolved_by, class_name: "User", optional: true

  validates :reason, presence: true, length: { maximum: 500 }

  scope :open, -> { where(resolved_at: nil) }

  def resolve!(actor)
    update!(resolved_at: Time.current, resolved_by: actor)
  end
end
