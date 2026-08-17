class LoginCodeMailer < ApplicationMailer
  def sign_in_code(email_address, code)
    @code = code
    mail to: email_address, subject: "#{code} is your plugins.omarchy.org sign-in code"
  end
end
