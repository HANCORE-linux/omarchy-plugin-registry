module SessionTestHelper
  # Most tests exercise features behind the step-up gate, so the default test
  # session counts as second-factor-verified; pass second_factor_verified:
  # false to exercise the gate itself.
  def sign_in_as(user, second_factor_verified: true)
    Current.session = user.sessions.create!(
      second_factor_verified_at: second_factor_verified ? Time.current : nil
    )

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end
  end

  def sign_out
    Current.session&.destroy!
    cookies.delete("session_id")
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
