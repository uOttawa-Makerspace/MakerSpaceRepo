class LearningModuleTrackController < DevelopmentProgramsController

  def index
    @skills = Skill.all
    @certifications = current_user.certifications
    @remaining_trainings = current_user.remaining_trainings
  end

  def start
    learning_module = LearningModule.find_by(id: params[:learning_module_id])
    learning_module_track = learning_module.learning_module_tracks.new
    learning_module_track.user = current_user
    if learning_module_track.save
      flash[:notice] = 'You have successfully started the learning module !'
    else
      flash[:alert] = 'An error has occurred while starting the learning module, please try again or contact uottawa.makerepo@uottawa.ca for support.'
    end
    redirect_to learning_area_path(learning_module.id)
  end

  def completed
    learning_module = LearningModule.find_by(id: params[:learning_module_id])
    if learning_module.learning_module_tracks.where(user: current_user).first.update(status: 'Completed')
      flash[:notice] = 'You have successfully completed the learning module !'
    else
      flash[:alert] = 'An error has occurred while completing the learning module, please try again or contact uottawa.makerepo@uottawa.ca for support.'
    end
    redirect_to learning_area_path(learning_module.id)
  end

end
