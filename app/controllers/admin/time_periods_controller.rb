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
    @time_period = TimePeriod.new(time_period_params)
    if @time_period.save
      redirect_to admin_time_periods_path
      flash[:notice] = I18n.t("admin_pages.time_periods.flash.created")
    else
      flash.now[:alert] = validation_message(@time_period, "errors.admin.time_periods.not_created")
      render :new, status: :unprocessable_content
    end
  end

  def update
    time_period = TimePeriod.find(params[:id])
    flash_write(time_period, "time_periods.not_updated", I18n.t("admin_pages.time_periods.flash.updated")) { time_period.update(time_period_params) }
    redirect_to admin_time_periods_path
  end

  def destroy
    time_period = TimePeriod.find(params[:id])
    flash_write(time_period, "time_periods.not_deleted", I18n.t("admin_pages.time_periods.flash.deleted"), destroy: true) { time_period.destroy }
    redirect_to admin_time_periods_path
  end

  private

  def time_period_params
    params.require(:time_period).permit(:name, :start_date, :end_date)
  end
end
