class TaskMailer < ApplicationMailer
  def renamed_user
    mail(
      to: params[:email],
      subject: "Makerepo | Your account username was renamed"
        )
  end

  def merged_user
    mail(to: params[:email],
         subject: "Makerepo | Duplicate accounts merged")
  end
end
