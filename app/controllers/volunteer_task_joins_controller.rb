# frozen_string_literal: true

class VolunteerTaskJoinsController < ApplicationController
  def create
    volunteer_join = VolunteerTaskJoin.new(volunteer_task_joins_params)
    volunteer_task = volunteer_join.volunteer_task
    if volunteer_task.volunteer_task_joins.active.user_type_volunteer.count < volunteer_task.joins || current_user.staff?
      volunteer_join.user_id = if current_user.staff?
                                 params[:volunteer_task_join][:user_id] || current_user.id
                               else
                                 current_user.id
                               end
      volunteer_join.user_type = volunteer_join.user.role.capitalize
      if volunteer_join.save!
        flash[:notice] = 'An user was successfully joined to this volunteer task.'
        staff_join = volunteer_task.volunteer_task_joins.where('volunteer_task_joins.user_type = ? OR volunteer_task_joins.user_type = ?', 'Staff', 'Admin').last
        staff_id = staff_join&.user&.id
        MsrMailer.send_notification_to_staff_for_joining_task(volunteer_task.id, volunteer_join.user_id, staff_id).deliver
        MsrMailer.send_notification_to_volunteer_for_joining_task(volunteer_task.id, volunteer_join.user_id, staff_id).deliver
      end
    else
      flash[:alert] = 'This task is already full'
    end
    redirect_back(fallback_location: root_path)
  end

  def remove
    # TODO: Make this 'destroy' instead of 'remove'
    user_id = params[:volunteer_task_join][:user_id]
    volunteer_task_id = params[:volunteer_task_join][:volunteer_task_id]
    volunteer_join = VolunteerTaskJoin.find_by(user_id: user_id,
                                               volunteer_task_id: volunteer_task_id)
    if volunteer_join.destroy
      flash[:notice] = 'User was removed from the Volunteer Task'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_back(fallback_location: root_path)
  end

  private

  def volunteer_task_joins_params
    params.require(:volunteer_task_join).permit(:volunteer_task_id, :user_id)
  end
end
