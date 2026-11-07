# frozen_string_literal: true

class AdminAreaController < SessionsController
  include AdminOnly

  before_action :current_user
  before_action :ensure_admin
end
