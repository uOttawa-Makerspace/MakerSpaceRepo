class Admin::TrainingsController < AdminAreaController
  layout "admin_area"
  before_action :set_spaces, only: %i[new edit]
  before_action :set_skills, only: %i[new edit]

  def index
    @trainings = Training.all.order(:name_en)
  end

  def new
    @new_training = Training.new
    @skills_en
    @skills_fr
  end

  def edit
    @training = Training.find(params[:id])
    @skills_en = @training.tokenize_info_en unless @training.list_of_skills_en.nil?
    @skills_fr = @training.tokenize_info_fr unless @training.list_of_skills_fr.nil?
    @options = @training.filter_by_attributes(params[:search])
  end

  def create
    serialize_skills
    @new_training = Training.new(training_params)
    @new_training.create_list_of_skills(params[:list_of_skills_en], params[:list_of_skills_fr])
    if @new_training.save
      flash[:notice] = "Training added successfully!"
    else
      flash[:alert] = "Input is invalid"
    end
    redirect_to admin_trainings_path
  end

  def update
    @changed_training = Training.find(params[:id])
    serialize_skills
    @changed_training.create_list_of_skills(params[:list_of_skills_en], params[:list_of_skills_fr])
    @changed_training.update(training_params)
    if @changed_training.save
      flash[:notice] = "Training updated successfully"
      redirect_to admin_trainings_path
    else      
      flash[:alert] = @changed_training.errors.full_messages
      redirect_to edit_admin_training_path
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
    params[:list_of_skills_en] = if params[:list_of_skills_en].nil?
      " "
    else
      params[:list_of_skills_en].join(', ')
                                 end
    params[:list_of_skills_fr] = if params[:list_of_skills_fr].nil?
      " "
    else
      params[:list_of_skills_fr].join(', ')
                                 end
  end

  def set_spaces
    @spaces ||= Space.order(:name)
  end

  def set_skills
    @skills = Skill.all.pluck(:name, :id)
  end
end
