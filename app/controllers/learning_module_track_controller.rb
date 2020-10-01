class LearningModuleTrackController < DevelopmentProgramsController

  def index
    @skills = Skill.all
    @certifications = current_user.certifications
    @remaining_trainings = current_user.remaining_trainings
  end

  def start
    if params[:learning_module_id].present?
      LearningModuleTrack.create(user_id: current_user.id, learning_module_id: params[:learning_module_id])
      flash[:notice] = 'You have successfully started the learning module !'
    else
      flash[:alert] = 'An error has occurred while starting the learning module, please try again or contact uottawa.makerepo@uottawa.ca for support.'
    end
    redirect_to learning_module_track_index_path
  end

  def completed
    if params[:id].present?
      LearningModuleTrack.find(params[:id]).update(status: 'Completed')
      flash[:notice] = 'You have successfully completed the learning module !'
    else
      flash[:alert] = 'An error has occurred while completing the learning module, please try again or contact uottawa.makerepo@uottawa.ca for support.'
    end
    redirect_to learning_module_track_index_path
  end

end
