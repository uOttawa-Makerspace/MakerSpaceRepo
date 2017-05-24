class StaffDashboardController < ApplicationController
  before_action :current_user
  before_action :ensure_admin

  def index
  end

  private

  def ensure_admin
    unless admin?
      redirect_to '/' and return
    end
  end

end
