class Admin::TrainingsController < AdminAreaController
  layout "admin_area"
  before_action :set_spaces, only: %i[new edit update create]
  before_action :set_skills, only: %i[new edit update create]

  def index
    @trainings = Training.all.order(:name_en)
  end

  def new
    @training = Training.new
    @skills_en = @training.list_of_skills_en&.split(',')
    @skills_fr = @training.list_of_skills_fr&.split(',')
  end

  def edit
    @training = Training.find(params[:id])
    @skills_en = @training.list_of_skills_en&.split(',')
    @skills_fr = @training.list_of_skills_fr&.split(',')
  end

  def create
    serialize_skills
    @training = Training.new(training_params)
    if @training.save
      flash[:notice] = "Training added successfully!"
      redirect_to admin_trainings_path
    else
      flash[:alert] = "Input is invalid"
      render :new, status: :unprocessable_content
    end
  end

  def update
    @training = Training.find(params[:id])
    serialize_skills
    if @training.update(training_params)
      flash[:notice] = "Training updated successfully"
      redirect_to admin_trainings_path
    else      
      flash[:alert] = "Input is invalid"
      render :edit, status: :unprocessable_content
    end
    
  end

  def destroy
    @changed_training = Training.find(params["id"])
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

  def serialize_skills
    params[:training][:list_of_skills_en] = params[:training][:list_of_skills_en]&.join(',')
                                 
    params[:training][:list_of_skills_fr] = params[:training][:list_of_skills_fr]&.join(', ')
  end

  def set_spaces
    @spaces ||= Space.order(:name)
  end

  def set_skills
    @skills = Skill.all.pluck(:name, :id)
  end
end
