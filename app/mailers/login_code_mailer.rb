class LoginCodeMailer < ApplicationMailer
  def sign_in_code(login_code)
    @login_code = login_code
    mail to: login_code.user.email_address, subject: "#{login_code.code} is your plugins.omarchy.org sign-in code"
  end
end
