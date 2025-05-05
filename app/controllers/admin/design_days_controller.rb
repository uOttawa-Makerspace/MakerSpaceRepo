class Admin::DesignDaysController < AdminAreaController
  before_action :make_variables, only: %i[show update data]
  skip_before_action :current_user, only: :data
  skip_before_action :ensure_admin, only: :data

  def show
  end

  def data
    # https://api.rubyonrails.org/classes/ActiveModel/Serializers/JSON.html#method-i-as_json
    render json:
             @design_day.as_json(
               include: :design_day_schedules,
               methods: %i[semester year]
             )
  end

  def update
    if @design_day.update(design_day_params)
      flash[:notice] = "Design day configuration updated"
      redirect_to @design_day
    else
      flash[:alert] = "Failed to update configuration"
      render :show, status: :unprocessable_entity
    end
  end

  private

  def make_variables
    @design_day ||= DesignDay.instance
    @design_day_schedules =
      @design_day.design_day_schedules.group_by(&:event_for)
    DesignDaySchedule.event_fors.each_key do |t|
      # make sure the others exist
      @design_day_schedules[t] ||= []
    end

    # DesignDaySchedule.event_fors.each_key do |t|
    #   @design_day_schedules << @design_day.design_day_schedules.build(event_for: t)
    # end
  end

  def design_day_params
    params.require(:design_day).permit(
      :day,
      :sheet_key,
      design_day_schedules_attributes: %i[
        id
        start
        end
        ordering
        title_en
        title_fr
        event_for
        _destroy
      ]
    )
  end
end
