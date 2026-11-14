class LearningModuleTrackController < DevelopmentProgramsController
  def index
    @skills = Skill.includes(trainings: :learning_modules)
    @certifications = current_user.certifications.includes(training_session: :training)
    @remaining_trainings = current_user.remaining_trainings
  end

  def start
    learning_module = LearningModule.find_by(id: params[:learning_module_id])
    if learning_module.nil?
      flash[:alert] = t("learning_module_track.flash.not_found")
      return redirect_to learning_area_index_path
    end

    begin
      LearningModuleTrack.for_user_and_module!(current_user, learning_module)
      flash[:notice] = t("learning_module_track.flash.started")
    rescue ActiveRecord::RecordInvalid => e
      flash[:alert] = validation_message(e.record, "errors.learning_area.not_started")
    rescue ActiveRecord::ActiveRecordError => e
      report_unexpected(e, source: "learning_module_track#start")
      flash[:alert] = "#{I18n.t('errors.learning_area.not_started')} #{unexpected_error_message}"
    end
    redirect_to learning_area_path(learning_module.id)
  end

  def completed
    learning_module = LearningModule.find_by(id: params[:learning_module_id])
    if learning_module.nil?
      flash[:alert] = t("learning_module_track.flash.not_found")
      return redirect_to learning_area_index_path
    end

    # A SCORM package reports its own completion
    if learning_module.scorm_package.attached?
      flash[:alert] = t("learning_module_track.flash.own_completion")
    elsif (track = learning_module.learning_module_tracks.find_by(user: current_user)).nil?
      flash[:alert] = I18n.t("errors.learning_area.not_started_yet")
    else
      write_flash(track, "errors.learning_area.not_completed", t("learning_module_track.flash.completed")) do
        track.update(status: "Completed")
      end
    end
    redirect_to learning_area_path(learning_module.id)
  end
end
