class ProficientProjectsController < DevelopmentProgramsController
  before_action :grant_access_to_project, only: [:show]
  before_action :only_admin_access, only: [:new, :create, :edit, :update, :destroy]
  before_action :set_proficient_project, only: [:show, :destroy, :edit, :update]
  before_action :set_training_categories, only: [:new, :edit]
  before_action :set_files_photos_videos, only: [:show, :edit]

  def index
    # if !params[:search].blank?
    #   query = params[:search]
    #   # sort_level = params[:sort_level]
    #   @proficient_projects = ProficientProject.
    #       where("LOWER(title) like LOWER(?) OR
    #              LOWER(level) like LOWER(?) OR
    #              LOWER(description) like LOWER(?)", "%#{query}%", "%#{query}%", "%#{query}%").paginate(:page => params[:page], :per_page => 30).page params[:page]
    # else
    #   @proficient_projects = ProficientProject.all.order(created_at: :desc).paginate(:page => params[:page], :per_page => 30)
    # end
    #
    @proficient_projects = ProficientProject.filter_attributes(get_filter_params).order(created_at: :desc).paginate(:page => params[:page], :per_page => 30)
  end

  def new
    @proficient_project = ProficientProject.new
    @training_levels = TrainingSession.return_levels
  end

  def show
    @project_requirements = @proficient_project.project_requirements
    @inverse_required_projects = @proficient_project.inverse_required_projects
    @proficient_projects_selected = ProficientProject.
        where.not(id: @project_requirements.pluck(:required_project_id) << @proficient_project.id).
        order(title: :asc)
  end

  def create
    @proficient_project = ProficientProject.new(proficient_project_params)
    if @proficient_project.save
      create_photos
      create_files
      create_videos
      flash[:notice] = "Proficient Project successfully created."
      render json: { redirect_uri: "#{proficient_project_path(@proficient_project.id)}" }
    else
      flash[:alert] = "Something went wrong"
      render json: @proficient_project.errors["title"].first, status: :unprocessable_entity
    end
  end

  def destroy
    @proficient_project.destroy
    respond_to do |format|
      format.html { redirect_to proficient_projects_path, notice: 'Proficient Project has been successfully deleted.' }
      format.json { head :no_content }
    end
  end

  def edit
    @training_levels = TrainingSession.return_levels
  end

  def update
    if @proficient_project.update(proficient_project_params)
      update_photos
      update_files
      update_videos
      flash[:notice] = "Proficient Project successfully updated."
      render json: { redirect_uri: "#{proficient_project_path(@proficient_project.id)}" }
    else
      flash[:alert] = "Unable to apply the changes."
      render json: @proficient_project.errors["title"].first, status: :unprocessable_entity
    end
  end

  private

  def grant_access_to_project
    unless current_user.dev_program? || current_user.admin? || current_user.staff?
      redirect_to root_path
      flash[:alert] = "You cannot access this area."
    end
  end

  def only_admin_access
    unless current_user.admin?
      redirect_to development_programs_path
      flash[:alert] = "Only admin members can access this area."
    end
  end

  def proficient_project_params
    params.require(:proficient_project).permit(:title, :description, :training_id, :level)
  end

  def create_photos
    params['images'].each do |img|
      dimension = FastImage.size(img.tempfile)
      Photo.create(image: img, proficient_project_id: @proficient_project.id, width: dimension.first, height: dimension.last)
    end if params['images'].present?
  end

  def create_files
    params['files'].each do |f|
      RepoFile.create(file: f, proficient_project_id: @proficient_project.id)
    end if params['files'].present?
  end

  def create_videos
    params['videos'].each do |f|
      Video.create(video: f, proficient_project_id: @proficient_project.id)
    end if params['videos'].present?
  end

  def set_proficient_project
    @proficient_project= ProficientProject.find(params[:id])
  end

  def set_training_categories
    @training_categories = Training.all.order(:name).pluck(:name, :id)
  end

  def set_files_photos_videos
    @photos = @proficient_project.photos || []
    @files = @proficient_project.repo_files.order(created_at: :asc)
    @videos = @proficient_project.videos.order(created_at: :asc)
  end

  def update_photos
    @proficient_project.photos.each do |img|
      if params['deleteimages'].include?(img.image_file_name) #checks if the file should be deleted
        Photo.destroy_all(image_file_name: img.image_file_name, proficient_project_id: @proficient_project.id)
      end
    end if params['deleteimages'].present?
    params['images'].each do |img|
      filename = img.original_filename.gsub(" ", "_");
      if @proficient_project.photos.where(image_file_name: filename).blank? #checks if file exists
        dimension = FastImage.size(img.tempfile)
        Photo.create(image: img, proficient_project_id: @proficient_project.id, width: dimension.first, height: dimension.last)
      else #updates existant files
        Photo.destroy_all(image_file_name: filename, proficient_project_id: @proficient_project.id)
        dimension = FastImage.size(img.tempfile)
        Photo.create(image: img, proficient_project_id: @proficient_project.id, width: dimension.first, height: dimension.last)
      end
    end if params['images'].present?
  end

  def update_files
    @proficient_project.repo_files.each do |f|
      if params['deletefiles'].include?(f.file_file_name) #checks if the file should be deleted
        RepoFile.destroy_all(file_file_name: f.file_file_name, proficient_project_id: @proficient_project.id)
      end
    end if params['deletefiles'].present?

    params['files'].each do |f|
      filename = f.original_filename.gsub(" ", "_")
      if @proficient_project.repo_files.where(file_file_name: filename).blank? #checks if file exists
        RepoFile.create(file: f, proficient_project_id: @proficient_project.id)
      else #updates existant files
        RepoFile.destroy_all(file_file_name: filename, proficient_project_id: @proficient_project.id)
        RepoFile.create(file: f, proficient_project_id: @proficient_project.id)
      end
    end if params['files'].present?
  end

  def update_videos
    @proficient_project.videos.each do |f|
      if params['deletevideos'].include?(f.video_file_name) #checks if the file should be deleted
        Video.destroy_all(video_file_name: f.video_file_name, proficient_project_id: @proficient_project.id)
      end
    end if params['deletevideos'].present?

    params['videos'].each do |f|
      filename = f.original_filename.gsub(" ", "_")
      if @proficient_project.videos.where(video_file_name: filename).blank? #checks if video exists
        Video.create(video: f, proficient_project_id: @proficient_project.id)
      else #updates existant videos
        Video.destroy_all(video_file_name: filename, proficient_project_id: @proficient_project.id)
        Video.create(video: f, proficient_project_id: @proficient_project.id)
      end
    end if params['videos'].present?
  end

  def get_filter_params
    params.permit(:search, :level, :category)
  end

  # def sort_level
  #   case params[:sort]
  #   when 'Beginner' then [:created_at, :desc]
  #   when 'Intermediate' then [:price, :asc]
  #   when 'Advanced' then [:updated_at, :desc]
  #   else [:created_at, :desc]
  #   end
  # end

end
