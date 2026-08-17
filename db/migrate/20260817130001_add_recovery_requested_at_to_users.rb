class AddRecoveryRequestedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    # Lost-factor recovery: a 72-hour timed escape hatch, cancellable by any
    # successful step-up (the real owner wins the race)
    add_column :users, :recovery_requested_at, :datetime
  end
end
