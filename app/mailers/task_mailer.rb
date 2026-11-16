class TaskMailer < ApplicationMailer
  def renamed_user
    mail(to: params[:email])
  end

  def merged_user
    mail(to: params[:email])
  end
end
