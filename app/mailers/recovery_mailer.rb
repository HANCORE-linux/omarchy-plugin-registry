class RecoveryMailer < ApplicationMailer
  def recovery_started(user)
    @user = user
    mail to: user.email_address, subject: "Security: account recovery started on plugins.omarchy.org"
  end
end
