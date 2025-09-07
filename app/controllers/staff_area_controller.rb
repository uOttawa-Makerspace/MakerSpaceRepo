# frozen_string_literal: true

class StaffAreaController < SessionsController
  before_action :current_user, :default_space, :define_spaces
  before_action :ensure_staff, except: %i[dismiss]

  private

  def ensure_staff
    unless signed_in?
      redirect_to login_path(back_to: request.fullpath)
      return
    end

    @user = current_user
    unless @user.staff? || @user.admin?
      redirect_to root_path
      flash[:alert] = 'You cannot access this area.'
    end
  end

  def default_space
    if current_user.space.present?
      @space = current_user.space
    else
      @space = Space.first
    end
  end

  def define_spaces
    @all_spaces ||= Space.order(:name)
  end
end
