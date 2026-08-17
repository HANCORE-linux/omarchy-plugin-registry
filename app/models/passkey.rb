# A WebAuthn credential. Counts as a publisher second factor (preferred over
# TOTP — unphishable) and signs the user in directly from the sign-in page.
class Passkey < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
end
