# frozen_string_literal: true

class StaffAreaController < SessionsController
  before_action :current_user, :ensure_staff
  before_action :default_space

  private

  def ensure_staff
    @user = current_user
    redirect_to '/' and return unless @user.staff?
  end

  def default_space
    @space = current_user.lab_sessions&.last&.space || Space.first
  end
end
