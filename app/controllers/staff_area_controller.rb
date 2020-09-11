# frozen_string_literal: true

class StaffAreaController < SessionsController
  before_action :current_user, :ensure_staff
  before_action :default_space
  before_action :define_spaces

  private

    def ensure_staff
      @user = current_user
      unless @user.staff? || @user.admin?
        redirect_to root_path
        flash[:alert] = 'You cannot access this area.'
      end
    end

    def default_space
      @space = current_user.lab_sessions&.last&.space || Space.first
    end

    def define_spaces
      @all_spaces ||= Space.order(:name)
    end
end
