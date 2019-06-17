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
      flash[:notice] = "An user was successfully joined to this volunteer task."
    end
  end

  def remove
    # TODO: Make this 'destroy' instead of 'remove'
    user_id = params[:volunteer_task_join][:user_id]
    volunteer_task_id = params[:volunteer_task_join][:volunteer_task_id]
    volunteer_join = VolunteerTaskJoin.find_by(:user_id => user_id,
                                               :volunteer_task_id => volunteer_task_id)
    if volunteer_join.destroy
      flash[:notice] = "User was removed from the Volunteer Task"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to :back
  end

  private

  def volunteer_task_joins_params
    params.require(:volunteer_task_join).permit(:volunteer_task_id, :user_id)
  end
end
