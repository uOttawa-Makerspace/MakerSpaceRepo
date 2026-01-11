# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  include ActionView::Helpers::SanitizeHelper 
  
  default from: "MakerRepo <ceedinfo@makerepo.com>"
  layout "mailer"
end
