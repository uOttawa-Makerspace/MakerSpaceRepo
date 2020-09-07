# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: 'MakerRepo <ceedinfo@makerepo.com>'
  layout 'mailer'
end
