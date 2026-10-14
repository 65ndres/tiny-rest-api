class PasswordResetMailer < ApplicationMailer
  def reset_code(user, code)
    @user = user
    @code = code
    mail(to: @user.email, subject: "Password Reset Code")
  end
end
