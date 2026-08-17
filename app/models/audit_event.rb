class AuditEvent < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :subject, polymorphic: true

  validates :action, presence: true

  scope :public_log, -> { where(public: true).order(created_at: :desc) }

  def self.record!(action:, subject:, actor: nil, metadata: {}, public: false)
    create!(user: actor, action:, subject:, metadata:, public:)
  end
end
