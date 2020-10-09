class LearningAreaController < DevelopmentProgramsController
  before_action :only_admin_access, only: %i[new create edit update destroy]
  before_action :set_learning_module, only: %i[show destroy edit update]
  before_action :set_training_categories, only: %i[new edit]
  before_action :set_training_levels, only: %i[new edit]
  before_action :set_files_photos_videos, only: %i[show edit]

  def index
    @learning_modules = LearningModule.filter_params(get_filter_params).order(created_at: :desc).paginate(page: params[:page], per_page: 30)
    @training_levels ||= TrainingSession.return_levels
    @training_categories_names = Training.all.order('name ASC').pluck(:name)
    flash.now[:alert_yellow] = "Please visit #{view_context.link_to "My Projects", proficient_projects_path(my_projects: true), class: "text-primary"} to access the proficient projects purchased".html_safe
    @learning_module_track = Proc.new { |learning_module| learning_module.learning_module_tracks.where(user: current_user) }
  end

  def new
    @learning_module = LearningModule.new
  end

  def show
    @valid_urls = @learning_module.extract_valid_urls
    @learning_module_track = @learning_module.learning_module_tracks.where(user: current_user)
  end

  def create
    @learning_module = LearningModule.new(learning_modules_params)
    if @learning_module.save
      create_photos
      create_files
      flash[:notice] = 'Learning Module has been successfully created.'
      render json: {redirect_uri: learning_area_path(@learning_module.id).to_s}
    else
      flash[:alert] = 'Something went wrong'
      render json: @learning_module.errors['title'].first, status: :unprocessable_entity
    end
  end

  def destroy
    @learning_module.destroy
    respond_to do |format|
      format.html { redirect_to learning_area_index_path, notice: 'Learning Module has been successfully deleted.' }
      format.json { head :no_content }
    end
  end

  def edit; end

  def update
    if @learning_module.update(learning_modules_params)
      update_photos
      update_files
      update_videos
      flash[:notice] = 'Learning module successfully updated.'
      render json: {redirect_uri: learning_area_path(@learning_module.id).to_s}
    else
      flash[:alert] = 'Unable to apply the changes.'
      render json: @learning_module.errors['title'].first, status: :unprocessable_entity
    end
  end

  private

    def only_admin_access
      unless current_user.admin?
        redirect_to development_programs_path
        flash[:alert] = 'Only admin members can access this area.'
      end
    end

    def learning_modules_params
      params.require(:learning_module).permit(:title, :description, :training_id, :level, :proficient, :cc, :badge_template_id)
    end

    def create_photos
      if params['images'].present?
        params['images'].each do |img|
          dimension = FastImage.size(img.tempfile)
          Photo.create(image: img, learning_module_id: @learning_module.id, width: dimension.first, height: dimension.last)
        end
      end
    end

    def create_files
      if params['files'].present?
        params['files'].each do |f|
          @repo = RepoFile.new(file: f, learning_module_id: @learning_module.id)
          unless @repo.save
            flash[:alert] = 'Make sure you only upload PDFs for the project files'
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
      if params['deleteimages'].present?
        @learning_module.photos.each do |img|
          if params['deleteimages'].include?(img.image.filename.to_s) # checks if the file should be deleted
            img.image.purge
            img.destroy
          end
        end
      end

      if params['images'].present?
        params['images'].each do |img|
          dimension = FastImage.size(img.tempfile)
          Photo.create(image: img, learning_module_id: @learning_module.id, width: dimension.first, height: dimension.last)
        end
      end
    end

    def update_files
      if params['deletefiles'].present?
        @learning_module.repo_files.each do |f|
          if params['deletefiles'].include?(f.file.filename.to_s) # checks if the file should be deleted
            f.file.purge
            f.destroy
          end
        end
      end

      if params['files'].present?

        params['files'].each do |f|
          repo = RepoFile.new(file: f, learning_module_id: @learning_module.id)
          unless repo.save
            flash[:alert] = 'Make sure you only upload PDFs for the project files, the PDFs were uploaded'
          end
        end

      end
    end

    def update_videos
      if params['deletevideos'].present?
        @learning_module.videos.each do |f|
          if params['deletevideos'].include?(f.video_file_name)
            f.video.purge
            f.destroy
          end
        end
      end
    end

    def get_filter_params
      params.permit(:search, :level, :category, :my_projects)
    end
end
