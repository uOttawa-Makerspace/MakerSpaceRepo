# frozen_string_literal: true

class UpdateMailer < ApplicationMailer
  def update_identity(user)
    @user = user
    mail(to: @user.email, subject: 'Please update your information')
  end
end
