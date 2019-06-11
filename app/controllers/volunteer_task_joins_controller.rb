class VolunteerTaskJoinsController < ApplicationController
  def create
    volunteer_join = VolunteerTaskJoin.new(volunteer_task_joins_params)
    if current_user.staff?
      volunteer_join.user_id = params[:volunteer_task_join][:user_id] || current_user.id
    else
      volunteer_join.user_id = current_user.id
    end
    volunteer_join.user_type = volunteer_join.user.role.capitalize
    if volunteer_join.save!
      redirect_to :back
      flash[:notice] = "You've successfully joined this volunteer task."
    end
  end

  private

  def volunteer_task_joins_params
    params.require(:volunteer_task_join).permit(:volunteer_task_id)
  end
end
