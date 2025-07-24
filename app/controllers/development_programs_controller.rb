# frozen_string_literal: true

class DevelopmentProgramsController < ApplicationController
  layout "development_program"
  before_action :current_user
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
    render layout: "application"
  end

  def badge_templates
    @certifications = current_user.certifications
    @digital_certs = []
    @manu_certs = []
    @prof_certs = []
    @certifications.each do |cert|
      if cert.training.skill_id == 1
        @digital_certs << cert
      elsif cert.training.skill_id == 2
        @manu_certs << cert
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
        @digital_trainings << training
      elsif training.skill_id == 2
        @manu_trainings << training
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
      redirect_to root_path,
                  alert:
                    (
                      if current_user.dev_program?
                        "You already joined the Program. You can already access it!"
                      else
                        "Something went wrong. Please try again later"
                      end
                    )
    end
  end

  private

  def grant_access
    unless current_user.dev_program? || current_user.admin? ||
             current_user.staff?
      redirect_to root_path
      flash[:alert] = "You cannot access this area."
    end
  end
end
