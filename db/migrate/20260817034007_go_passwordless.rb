# Auth mirrors Cortex/Herald: no passwords, ever. Sign-in is an emailed
# one-time code; TOTP (and eventually passkeys) is the publisher second factor.
class GoPasswordless < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :password_digest, :string, null: false

    create_table :login_codes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :code, null: false
      t.datetime :consumed_at
      t.timestamps
    end
    add_index :login_codes, [ :user_id, :code ]
  end
end
