# frozen_string_literal: true

class AdminAreaController < SessionsController
  before_action :current_user
  before_action :ensure_admin

  private

  def ensure_admin
    @user = current_user
    redirect_to '/' and return unless @user.admin?
  end
end
