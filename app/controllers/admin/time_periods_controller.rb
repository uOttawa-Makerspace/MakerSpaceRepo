# frozen_string_literal: true

class Admin::TimePeriodsController < AdminAreaController
  layout "admin_area"

  def index
    @time_periods = TimePeriod.all
  end

  def new
    @time_period = TimePeriod.new
  end

  def edit
    @time_period = TimePeriod.find(params[:id])
  end

  def create
    time_period = TimePeriod.new(time_period_params)
    if time_period.save!
      redirect_to admin_time_periods_path
      flash[:notice] = "You have successfully created a new time period!"
    end
  end

  def update
    time_period = TimePeriod.find(params[:id])
    if time_period.update(time_period_params)
      flash[:notice] = "Time Period updated"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to admin_time_periods_path
  end

  def destroy
    time_period = TimePeriod.find(params[:id])
    if time_period.destroy
      flash[:notice] = "Time Period Deleted"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to admin_time_periods_path
  end

  private

  def time_period_params
    params.require(:time_period).permit(:name, :start_date, :end_date)
  end
end
