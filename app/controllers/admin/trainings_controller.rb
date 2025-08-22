class Admin::TrainingsController < AdminAreaController
  layout "admin_area"
  before_action :changed_training, only: %i[update destroy]
  before_action :set_spaces, only: %i[new edit]
  before_action :set_skills, only: %i[new edit]

  def index
    @trainings = Training.all.order(:name_en)
  end

  def new
    @new_training = Training.new
  end

  def edit
    @training = Training.find(params[:id])
  end

  def create
    @new_training = Training.new(training_params)
    if @new_training.save
      flash[:notice] = "Training added successfully!"
    else
      flash[:alert] = "Input is invalid"
    end
    redirect_to admin_trainings_path
  end

  def update
    @changed_training.update(training_params)
    if @changed_training.save
      flash[:notice] = "Training renamed successfully"
    else
      flash[:alert] = "Input is invalid"
    end
    redirect_to admin_trainings_path
  end

  def destroy
    flash[
      :notice
    ] = "Training removed successfully" if @changed_training.destroy
    redirect_to admin_trainings_path
  end

  private

  def training_params
    params.require(:training).permit(
      :name_en,
      :name_fr,
      :skill_id,
      :description_en,
      :description_fr,
      :training_level,
      :list_of_skills_en,
      :list_of_skills_fr,
      :has_badge,
      space_ids: []
    )
  end

  def changed_training
    @changed_training = Training.find(params["id"])
  end

  def set_spaces
    @spaces ||= Space.order(:name)
  end

  def set_skills
    @skills = Skill.all.pluck(:name, :id)
  end
end
