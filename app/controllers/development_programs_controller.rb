# frozen_string_literal: true

class DevelopmentProgramsController < SessionsController
  require_authorization
  skip_authorization only: %i[index join_development_program],
                     reason: "#{Authorization::ROLLOUT_PENDING}index and join_development_program are not behind grant_access"
  before_action :current_user
  before_action :signed_in, only: :join_development_program
  before_action :with_development_header, except: :index

  # HACK: hardcode exception for this controller's index page only
  before_action :grant_access,
                except: %i[join_development_program],
                unless:
                  lambda {
                    controller_name ==
                      DevelopmentProgramsController.controller_name &&
                      action_name == "index"
                  }

  def index
    # HACK: before_action: :no_container means this gets inherited
    no_container
    
    render layout: "application"
  end

  def all_badges
    @certifications = current_user.certifications_with_training
    @digital_certs = []
    @manu_certs = []
    @prof_certs = []
    @certifications.each do |cert|
      if cert.training.skill_id == 1
        @manu_certs << cert
      elsif cert.training.skill_id == 2
        @digital_certs << cert
      else
        @prof_certs << cert
      end
      
    end
    @remaining_trainings = current_user.remaining_trainings
    @digital_trainings = []
    @manu_trainings = []
    @prof_trainings = []
    @remaining_trainings.each do |training|
      if training.skill_id == 1
        @manu_trainings << training
      elsif training.skill_id == 2
        @digital_trainings << training
      else
        @prof_trainings << training
      end
      
    end
  end

  def skills
    @skills = Skill.includes(trainings: %i[proficient_projects learning_modules])
    @certifications = current_user.certifications.includes(training_session: :training)
    @remaining_trainings = current_user.remaining_trainings
  end

  def join_development_program
    if Program.join(current_user, Program::DEV_PROGRAM)
      flash[:notice] = "You've joined the Development Program"
      redirect_to development_programs_path
    else
      redirect_to root_path, alert: "You already joined the Program. You can already access it!"
    end
  end

  private

  def grant_access
    return signed_in unless signed_in?

    record_authorization!(:signed_in)
  end
end
