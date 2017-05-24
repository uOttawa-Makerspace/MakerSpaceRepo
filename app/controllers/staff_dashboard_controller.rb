class StaffDashboardController < ApplicationController
  before_action :current_user
  before_action :ensure_admin

  private

  def ensure_admin
    unless admin?
      redirect_to '/' and return
    end
  end

end
