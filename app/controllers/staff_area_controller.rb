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

  # The space the page works in: the saved space when the user may work in it, else the first space they may work
  # in (User#current_space). Nil when they may work in none.
  def default_space
    @space = current_user.current_space
  end

  def define_spaces
    @all_spaces ||= current_user.workable_spaces.order(:name)
  end

  # For the actions that need @space: with no space to work in, the page says so (JSON and scripts get a 403).
  def require_space
    return if @space

    respond_to do |format|
      format.html { render "staff_dashboard/no_space", layout: true }
      format.json { render json: { error: I18n.t("common.no_assigned_spaces") }, status: :forbidden }
      format.any { head :forbidden }
    end
  end
end
