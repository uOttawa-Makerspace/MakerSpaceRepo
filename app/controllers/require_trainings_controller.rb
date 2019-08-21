class RequireTrainingsController < VolunteerTasksController
  def create
    require_training = RequireTraining.new(require_training_params)
    if require_training.save!
      redirect_to :back
      flash[:notice] = "You've successfully added a required training for this volunteer task."
    else
      flash[:notice] = "Something went wrong"
    end
  end

  def remove_trainings
    require_training = RequireTraining.where(require_training_params).last
    if require_training && current_user.staff?
      require_training.destroy
      flash[:notice] = "You've successfully deleted this required training"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to :back
  end

  private

  def require_training_params
    params.require(:require_training).permit(:volunteer_task_id, :training_id)
  end
end
