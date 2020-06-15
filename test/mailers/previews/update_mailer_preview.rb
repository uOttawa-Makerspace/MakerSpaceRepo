# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/update_mailer
class UpdateMailerPreview < ActionMailer::Preview
  def update_identity
    UpdateMailer.update_identity(User.first)
  end
end
