class MomusRemediations < ActiveRecord::Migration[8.1]
  def change
    # Claim challenges are now derived (HMAC of publisher+user), not stored
    remove_column :publishers, :claim_challenge, :string

    # Brute-force lockout for emailed sign-in codes
    add_column :login_codes, :attempts, :integer, null: false, default: 0

    # Step-up: sensitive actions require a second factor verified in THIS session
    add_column :sessions, :second_factor_verified_at, :datetime

    # (A sort-key backfill lived here originally; it is superseded by the
    # self-contained backfill in 20260817060001.)
  end
end
