# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: 'uottawa.makerepo@gmail.com'
  layout 'mailer'
end
