class StaffDashboardController < ApplicationController
  before_action :current_user, :ensure_admin

  def index
  end

  private

  def ensure_staff
    unless staff?
      redirect_to '/' and return
    end
  end

end
