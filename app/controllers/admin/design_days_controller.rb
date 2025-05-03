class Admin::DesignDaysController < AdminAreaController
  def show
    @design_day = DesignDay.instance
    @design_day_schedules = @design_day.design_day_schedules
  end

  def update
    @design_day = DesignDay.instance
    if @design_day.update(design_day_params)
      flash[:notice] = "Design day configuration updated"
      redirect_to @design_day
    else
      flash[:alert] = "Failed to update configuration"
      render :show, status: :unprocessable_entity
    end
  end

  private

  def design_day_params
    params.require(:design_day).permit(
      :day,
      :sheet_key,
      design_day_schedules_attributes: [
        :id, :start, :end, :ordering, :title_en, :title_fr, :event_for
      ]
    )
  end
end
