class AddStepUpFailuresToSessions < ActiveRecord::Migration[8.1]
  def change
    # Session-level failure budget for step-up guesses (IP throttles alone can
    # be rotated around)
    add_column :sessions, :step_up_failures, :integer, null: false, default: 0
  end
end
