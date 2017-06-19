class TacMailer < ApplicationMailer
  def send_reminder_email email
    mail(to: email, subject: "Please sign the terms and conditions!", body: "https://www.youtube.com/watch?v=JEmAygu0NEk")
  end
end
