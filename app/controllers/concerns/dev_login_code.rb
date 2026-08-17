# Exposes sign-in codes in development so the flow is testable without email
# (the Cortex DevMagicLink pattern), with a guard that raises if a code would
# ever leak through flash outside development.
module DevLoginCode
  extend ActiveSupport::Concern

  included do
    after_action :ensure_login_code_not_leaked
  end

  private

  def expose_login_code_in_dev(login_code)
    return unless Rails.env.development? && login_code.present?
    flash[:dev_login_code] = login_code.plaintext_code
    response.set_header("X-Login-Code", login_code.plaintext_code)
  end

  def ensure_login_code_not_leaked
    return if Rails.env.development?
    raise SecurityError, "Login code leaked via flash in #{Rails.env}!" if flash[:dev_login_code].present?
  end
end
