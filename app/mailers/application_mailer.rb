# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: 'ceedinfo@makerepo.com'
  layout 'mailer'
end
