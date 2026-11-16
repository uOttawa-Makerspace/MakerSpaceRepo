class Admin::TrainingsController < AdminAreaController
  SKILL_LIST_KEYS = %i[list_of_skills_en list_of_skills_fr].freeze

  layout "admin_area"
  before_action :set_spaces, only: %i[new edit update create]
  before_action :set_skills, only: %i[new edit update create]
  before_action :require_training_params, only: %i[create update]

  def index
    @trainings = Training.includes(:skill).order(:name_en)
    @spaces_by_training = spaces_by_training
    @session_counts = TrainingSession.reorder(nil).group(:training_id, :space_id).count
    @certification_counts =
      Certification.joins(:training_session).group("training_sessions.training_id", "training_sessions.space_id").count
  end

  def new
    @training = Training.new
    assign_selected_skills
  end

  def edit
    @training = Training.find(params[:id])
    assign_selected_skills
  end

  def create
    @training = Training.new(training_params)
    if @training.save
      flash[:notice] = t("admin_area.trainings.flash.created")
      redirect_to admin_trainings_path
    else
      flash[:alert] = t("admin_area.input_invalid")
      render :new, status: :unprocessable_content
    end
  end

  def update
    @training = Training.find(params[:id])
    if @training.update(training_params)
      flash[:notice] = t("admin_area.trainings.flash.updated")
      redirect_to admin_trainings_path
    else      
      flash[:alert] = t("admin_area.input_invalid")
      render :edit, status: :unprocessable_content
    end
    
  end

  def destroy
    @changed_training = Training.find(params["id"])
    flash_write(@changed_training, "trainings.not_deleted", t("admin_area.trainings.flash.deleted"), destroy: true) { @changed_training.destroy }
    redirect_to admin_trainings_path
  end

  private

  def spaces_by_training
    Space.joins(:trainings).order(:name).select("spaces.*, spaces_trainings.training_id AS training_id").group_by(&:training_id)
  end

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

  # Each list is handed to the model as one comma separated string; the model strips the names and
  # drops blanks. A list that is absent or null in the request is left as it is.
  def skill_lists
    SKILL_LIST_KEYS.select { |key| !params[:training][key].nil? }.to_h { |key| [key, params[:training][key].join(",")] }
  end

  def assign_selected_skills
    @skills_en = Training.split_skills(@training.list_of_skills_en)
    @skills_fr = Training.split_skills(@training.list_of_skills_fr)
  end

  def set_spaces
    @spaces ||= Space.order(:name)
  end

  def set_skills
    @skills = Skill.all.pluck(:name, :id)
  end
end
