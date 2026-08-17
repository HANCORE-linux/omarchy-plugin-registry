class LoginCodeMailer < ApplicationMailer
  # The code arrives ENCRYPTED (job-queue arguments are persistent rows) and
  # is decrypted only at render time
  def sign_in_code(email_address, encrypted_code)
    @code = LoginCode.decrypt_for_delivery(encrypted_code)
    mail to: email_address, subject: "#{@code} is your plugins.omarchy.org sign-in code"
  end
end
