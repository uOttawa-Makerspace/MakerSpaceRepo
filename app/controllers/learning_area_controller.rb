class LearningAreaController < DevelopmentProgramsController
  before_action :only_admin_access, only: %i[new create edit update destroy]
  before_action :set_learning_module, only: %i[show destroy edit update scorm_launch serve_scorm_asset]
  before_action :set_training_categories, only: %i[new edit]
  before_action :set_training_levels, only: %i[new edit]

  def index
    @skills = Skill.all
    @learning_module_track =
      proc do |learning_module|
        learning_module.learning_module_tracks.where(user: current_user)
      end
    @all_learning_modules =
      proc { |training| training.learning_modules.order(:order) }
    @learning_modules_completed =
      proc do |training, level|
        training
          .learning_modules
          .joins(:learning_module_tracks)
          .where(
            learning_module_tracks: {
              user: current_user,
              status: 'Completed'
            }
          )
          .where(learning_modules: { level: level })
      end
    @total_learning_modules_per_level =
      proc { |training, level| training.learning_modules.where(level: level) }
  end

  def new
    @learning_module = LearningModule.new
  end

  def show
    @valid_urls = @learning_module.extract_valid_urls
    @learning_module_track =
      @learning_module.learning_module_tracks.where(user: current_user)
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
      if @learning_module.scorm_package.attached? && scorm_package_changed?
        @learning_module.update!(scorm_status: :processing)
        ExtractScormJob.perform_later(@learning_module.id)
      end
      redirect_to learning_area_path(@learning_module.id)
    else
      render :edit
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

    service = ActiveStorage::Blob.service
    key = "#{@learning_module.scorm_prefix}/#{params[:path]}"

    return head :not_found unless service.exist?(key)

    send_data service.download(key),
              content_type: Marcel::MimeType.for(name: params[:path]),
              disposition: :inline
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
    redirect_to development_programs_path,
                alert: 'Only admin members can access this area.'
  end

  def set_learning_module
    @learning_module = LearningModule.find(params[:id])
  end

  def scorm_package_changed?
    @learning_module.scorm_package.blob.created_at > 10.seconds.ago
  end

  def set_training_categories
    @training_categories = Training.all.order(:name).pluck(:name, :id)
  end

  def set_training_levels
    @training_levels ||= TrainingSession.return_levels
  end

  def learning_module_params
    params.require(:learning_module).permit(
      :title,
      :description,
      :training_id,
      :level,
      :cc,
      :badge_template_id,
      :scorm_package,
      photos: [],
      project_files: [],
      videos: []
    )
  end
end
