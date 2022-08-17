class LearningAreaController < DevelopmentProgramsController
  before_action :only_admin_access, only: %i[new create edit update destroy]
  before_action :set_learning_module, only: %i[show destroy edit update]
  before_action :set_training_categories, only: %i[new edit]
  before_action :set_training_levels, only: %i[new edit]
  before_action :set_files_photos_videos, only: %i[show edit]

  def index
    @skills = Skill.all
    @learning_module_track =
      Proc.new do |learning_module|
        learning_module.learning_module_tracks.where(user: current_user)
      end
    @all_learning_modules =
      Proc.new { |training| training.learning_modules.order(:order) }
    @learning_modules_completed =
      Proc.new do |training, level|
        training
          .learning_modules
          .joins(:learning_module_tracks)
          .where(
            learning_module_tracks: {
              user: current_user,
              status: "Completed"
            }
          )
          .where(learning_modules: { level: level })
      end
    @total_learning_modules_per_level =
      Proc.new do |training, level|
        training.learning_modules.where(level: level)
      end
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
    @learning_module = LearningModule.new(learning_modules_params)
    if @learning_module.save
      begin
        create_photos
      rescue FastImage::ImageFetchFailure,
             FastImage::UnknownImageType,
             FastImage::SizeNotFound => e
        @learning_module.destroy
        redirect_to request.path,
                    alert:
                      "Something went wrong while uploading photos, try again later."
      else
        create_files
        redirect_to learning_area_path(@learning_module.id),
                    notice: "Learning Module has been successfully created."
      end
    else
      flash[:alert] = "Something went wrong"
      @training_levels ||= TrainingSession.return_levels
      @training_categories = Training.all.order(:name).pluck(:name, :id)
      render "new", status: 422
    end
  end

  def destroy
    @learning_module.destroy
    respond_to do |format|
      format.html do
        redirect_to learning_area_index_path,
                    notice: "Learning Module has been successfully deleted."
      end
      format.json { head :no_content }
    end
  end

  def edit
  end

  def update
    if @learning_module.update(learning_modules_params)
      update_files
      update_videos
      begin
        update_photos
      rescue FastImage::ImageFetchFailure,
             FastImage::UnknownImageType,
             FastImage::SizeNotFound => e
        redirect_to learning_area_path(@learning_module.id),
                    alert_yellow:
                      "Something went wrong while uploading photos, try again later. Other changes have been saved."
      else
        redirect_to learning_area_path(@learning_module.id),
                    notice: "Learning module successfully updated."
      end
    else
      flash[:alert] = "Unable to apply the changes."
      render json: @learning_module.errors["title"].first,
             status: :unprocessable_entity
    end
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
                      notice: "Successfully reordered the learning modules!"
        end
        format.json { render json: { status: :ok } }
      end
    else
      flash[
        :alert
      ] = "Unable to re-order the learning modules. Please try again later..."
    end
  end

  private

  def only_admin_access
    unless current_user.admin?
      redirect_to development_programs_path,
                  alert: "Only admin members can access this area."
    end
  end

  def learning_modules_params
    params.require(:learning_module).permit(
      :title,
      :description,
      :training_id,
      :level,
      :cc,
      :badge_template_id
    )
  end

  def create_photos
    if params["images"].present?
      params["images"].each do |img|
        dimension = FastImage.size(img.tempfile, raise_on_failure: true)
        Photo.create(
          image: img,
          learning_module_id: @learning_module.id,
          width: dimension.first,
          height: dimension.last
        )
      end
    end
  end

  def create_files
    if params["files"].present?
      params["files"].each do |f|
        @repo = RepoFile.new(file: f, learning_module_id: @learning_module.id)
        unless @repo.save
          flash[:alert] = "Make sure you only upload PDFs for the project files"
        end
      end
    end
  end

  def set_learning_module
    @learning_module = LearningModule.find(params[:id])
  end

  def set_training_categories
    @training_categories = Training.all.order(:name).pluck(:name, :id)
  end

  def set_training_levels
    @training_levels ||= TrainingSession.return_levels
  end

  def set_files_photos_videos
    @photos = @learning_module.photos || []
    @files = @learning_module.repo_files.order(created_at: :asc)
    @videos = @learning_module.videos.processed.order(created_at: :asc)
  end

  def update_photos
    if params["deleteimages"].present?
      @learning_module.photos.each do |img|
        if params["deleteimages"].include?(img.image.filename.to_s)
          # checks if the file should be deleted
          img.image.purge
          img.destroy
        end
      end
    end

    if params["images"].present?
      params["images"].each do |img|
        dimension = FastImage.size(img.tempfile, raise_on_failure: true)
        Photo.create(
          image: img,
          learning_module_id: @learning_module.id,
          width: dimension.first,
          height: dimension.last
        )
      end
    end
  end

  def update_files
    if params["deletefiles"].present?
      @learning_module.repo_files.each do |f|
        if params["deletefiles"].include?(f.file.filename.to_s)
          # checks if the file should be deleted
          f.file.purge
          f.destroy
        end
      end
    end

    if params["files"].present?
      params["files"].each do |f|
        repo = RepoFile.new(file: f, learning_module_id: @learning_module.id)
        unless repo.save
          flash[
            :alert
          ] = "Make sure you only upload PDFs for the project files, the PDFs were uploaded"
        end
      end
    end
  end

  def update_videos
    videos_id = params["deletevideos"]
    if videos_id.present?
      videos_id = videos_id.split(",").uniq.map { |id| id.to_i }
      @learning_module.videos.each do |f|
        if (f.video.pluck(:id) & videos_id).any?
          videos_id.each do |video_id|
            video = f.video.find(video_id)
            video.purge
          end
          f.destroy unless f.video.attached?
        end
      end
    end
  end

  def get_filter_params
    params.permit(:search, :level, :category, :my_projects)
  end
end
