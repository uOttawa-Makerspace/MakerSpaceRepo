class JobOrdersController < ApplicationController
  before_action :current_user
  before_action :signed_in
  before_action :grant_access, only: %w[index new create update destroy]

  def index
    @job_orders = @user.job_orders
  end

  def new
    @job_order = JobOrder.new
  end

  def edit

  end

  def create

  end

  def update

  end

  def destroy

  end

  def admin
    @job_orders = JobOrder.all
  end

  def settings
    @service_groups = JobServiceGroup.all.order(:job_type_id)
    @services = JobService.all.order(:job_service_group_id)
    @options = JobOption.all
  end

  private

  def grant_access
    unless current_user.staff? || current_user.admin?
      flash[:alert] = 'You cannot access this area.'
      redirect_to root_path
    end
  end

end
