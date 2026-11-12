# frozen_string_literal: true

class StaffAreaController < SessionsController
  require_authorization
  before_action :current_user, :default_space, :define_spaces
  before_action :ensure_staff, except: %i[dismiss]

  private

  def ensure_staff
    return redirect_to(login_path(back_to: login_back_to)) unless signed_in?

    @user = current_user
    if @user.staff? || @user.admin?
      record_authorization!(:staff)
    else
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
    # The user's saved space is always listed so the picker shows the space they are in.
    @all_spaces ||= current_user.workable_spaces.or(Space.where(id: current_user.space_id)).order(:name)
  end
end
