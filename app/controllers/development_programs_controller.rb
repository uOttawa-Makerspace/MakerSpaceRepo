# frozen_string_literal: true

class DevelopmentProgramsController < SessionsController
  require_authorization
  skip_authorization only: %i[index join_development_program],
                     reason: "Not gated by grant_access today; the authorization rollout adds the checks"
  before_action :current_user
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
    @certifications = current_user.certifications
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
    @skills = Skill.all
    @certifications = current_user.certifications
    @remaining_trainings = current_user.remaining_trainings
    @proficient_projects_awarded =
      proc do |training|
        training.proficient_projects.where(
          id: current_user.order_items.awarded.pluck(:proficient_project_id)
        )
      end
    @learning_modules_completed =
      proc do |training|
        training.learning_modules.where(
          id:
            current_user.learning_module_tracks.completed.pluck(
              :learning_module_id
            )
        )
      end
    @recomended_hours =
      proc do |training, levels|
        training.learning_modules.where(level: levels).count +
          training.proficient_projects.where(level: levels).count
      end
  end

  def join_development_program
    program =
      Program.new(user_id: current_user.id, program_type: Program::DEV_PROGRAM)
    if program.save
      flash[:notice] = "You've joined the Development Program"
      redirect_to development_programs_path
    else
      redirect_to root_path, alert: join_refusal(program)
    end
  end

  private

  def join_refusal(program)
    return "You already joined the Program. You can already access it!" if current_user.dev_program?

    validation_message(program, "errors.development_programs.not_joined")
  end

  def grant_access
    return signed_in unless signed_in?

    authorized!(:signed_in)
  end
end
