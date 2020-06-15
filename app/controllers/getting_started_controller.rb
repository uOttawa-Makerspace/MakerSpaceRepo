# frozen_string_literal: true

class GettingStartedController < SessionsController
  skip_before_action :session_expiry
  before_action :current_user

  layout 'getting_started'

  def setting_up_account; end

  def creating_repository; end
end
