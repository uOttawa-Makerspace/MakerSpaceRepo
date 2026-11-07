class Admin::TrainingsController < AdminAreaController
  SKILL_LIST_KEYS = %i[list_of_skills_en list_of_skills_fr].freeze

  layout "admin_area"
  before_action :set_spaces, only: %i[new edit update create]
  before_action :set_skills, only: %i[new edit update create]
  before_action :require_training_params, only: %i[create update]

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
    params
      .require(:training)
      .permit(
        :name_en,
        :name_fr,
        :skill_id,
        :description_en,
        :description_fr,
        :has_badge,
        space_ids: []
      )
      .merge(skill_lists)
  end

  # The skill lists arrive as arrays of select options (including a blank
  # one); a malformed body is refused rather than failing half-way.
  def require_training_params
    training = params.require(:training)
    return if training.is_a?(ActionController::Parameters) && SKILL_LIST_KEYS.all? { |key| skill_list_param?(training[key]) }

    head :bad_request
  end

  def skill_list_param?(value)
    value.nil? || (value.is_a?(Array) && value.all?(String))
  end

  # Stored as one comma separated string, without blanks or padding. A list
  # that is not in the request is left as it is.
  def skill_lists
    SKILL_LIST_KEYS.select { |key| params[:training].key?(key) }.to_h do |key|
      [key, params[:training][key].map(&:strip).compact_blank.join(",")]
    end
  end

  def set_spaces
    @spaces ||= Space.order(:name)
  end

  def set_skills
    @skills = Skill.all.pluck(:name, :id)
  end
end
