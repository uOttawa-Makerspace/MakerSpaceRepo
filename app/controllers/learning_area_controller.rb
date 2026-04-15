class LearningAreaController < DevelopmentProgramsController
  before_action :only_admin_access, only: %i[new create edit update destroy]
  before_action :set_learning_module,
                only: %i[
                  show
                  destroy
                  edit
                  update
                  scorm_launch
                  serve_scorm_asset
                  scorm_commit
                ]

  before_action :form_training_data, only: %i[new edit create update]

  def index
    # Get all modules, group by training and separate into subskills. Modules
    # with no subskill get put in a separate subskill page.
    @learning_modules =
      LearningModule
        .with_attached_photos
        .includes(:training)
        .group_by(&:training)
        .sort_by { |training, _| training.name }
        .to_h
        .transform_values do |modules|
          modules.sort_by { |m| LearningModule.levels.keys.index(m.level) }
        end
  end

  def new
    @learning_module = LearningModule.new
  end

  def show
  end

  def subskill
    @subskill = params[:subskill]
    @learning_modules = LearningModule.where(subskill: params[:subskill])
  end

  def create
    @learning_module = LearningModule.new(learning_module_params)
    if @learning_module.save
      redirect_to learning_area_path(@learning_module.id),
                  notice: 'Learning Module has been successfully created.'
    else
      flash[:alert] = 'Something went wrong'
      render 'new', status: :unprocessable_content
    end
  end

  def destroy
    @learning_module.destroy
    respond_to do |format|
      format.html do
        redirect_to learning_area_index_path,
                    notice: 'Learning Module has been successfully deleted.'
      end
      format.json { head :no_content }
    end
  end

  def edit
  end

  def update
    if @learning_module.update(learning_module_params)
      redirect_to learning_area_path(@learning_module.id),
                  notice: 'Learning module successfully updated.'
    else
      flash.now[:alert] = 'Unable to apply the changes.'
      render :edit, status: :unprocessable_entity
    end
  end

  def scorm_launch
    unless @learning_module.scorm_ready?
      return(
        render json: {
                 error: 'SCORM package not ready'
               },
               status: :unprocessable_entity
      )
    end

    redirect_to scorm_asset_learning_area_url(
                  @learning_module,
                  path: @learning_module.scorm_entry_point
                ),
                allow_other_host: true
  end

  def serve_scorm_asset
    return head :not_found unless @learning_module.scorm_ready?

    # Reconstruct blob key from request path and stored prefix
    key = "#{@learning_module.scorm_prefix}/#{params[:path]}"

    blob = @learning_module.scorm_package_files.blobs.find_by(key: key)
    return head :not_found unless blob

    send_data blob.download,
              content_type: blob.content_type,
              disposition: :inline
  end

  def scorm_commit
    current_user
      .learning_module_tracks
      .find_or_create_by!(learning_module_id: params[:id])
      .update(scorm_state: scorm_state_params)

    head :ok
  end

  def reorder
    if params[:data].present?
      lm_order =
        LearningModule.where(id: params[:data]).order(:order).pluck(:order)
      params[:data].each_with_index do |lm, i|
        LearningModule.find(lm).update(order: lm_order[i])
      end

      respond_to do |format|
        format.html do
          redirect_to learning_area_index_path,
                      notice: 'Successfully reordered the learning modules!'
        end
        format.json { render json: { status: :ok } }
      end
    else
      flash[
        :alert
      ] = 'Unable to re-order the learning modules. Please try again later...'
    end
  end

  private

  def only_admin_access
    return if current_user.admin?
    redirect_to learning_area_index_path
  end

  # Can get module by numeric ID or by a custom shortcut
  def set_learning_module
    @learning_module =
      if params[:shortcut]
        LearningModule.find_by!(shortcut_name: params[:shortcut])
      else
        LearningModule.find(params[:id])
      end
  end

  def form_training_data
    @training_categories ||= Training.all.order(:name).pluck(:name, :id)
    @training_levels ||= LearningModule.levels.values
    @subskills ||= LearningModule.unscope(:order).distinct.pluck(:subskill)
  end

  def learning_module_params
    params.require(:learning_module).permit(
      :title,
      :description,
      :shortcut_name,
      :training_id,
      :level,
      :cc,
      :subskill,
      :badge_template_id,
      :scorm_package,
      :scorm_enabled,
      photos: [],
      project_files: [],
      videos: []
    )
  end

  def scorm_state_params
    # Keys lifted from flattened scorm-again format
    params
      .permit(
        :'cmi.completion_status',
        :'cmi.exit',
        :'cmi.location',
        :'cmi.progress_measure',
        :'cmi.score.scaled',
        :'cmi.score.raw',
        :'cmi.score.min',
        :'cmi.score.max',
        :'cmi.session_time',
        :'cmi.success_status',
        :'cmi.suspend_data',
        :'cmi.comments_from_learner',
        learner_preference: %i[
          audio_level
          language
          delivery_speed
          audio_captioning
        ]
      )
      .tap do |whitelisted|
        # Limit suspend data to 64kb, per the standard
        if (suspend_data = whitelisted[:'cmi.suspend_data']).is_a?(String) &&
             suspend_data.length > 64_000
          raise ActionController::BadRequest,
                'suspend_data exceeds 64k character limit'
        end
      end
  end
end
