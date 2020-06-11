class ProficientProjectsController < DevelopmentProgramsController
  before_action :only_admin_access, only: [:new, :create, :edit, :update, :destroy]
  before_action :set_proficient_project, only: [:show, :destroy, :edit, :update]
  before_action :grant_access_to_project, only: [:show]
  before_action :set_training_categories, only: [:new, :edit]
  before_action :set_badge_templates, only: [:new, :edit]
  before_action :set_files_photos_videos, only: [:show, :edit]

  def index
    @proficient_projects = ProficientProject.filter_attributes(get_filter_params).order(created_at: :desc).paginate(:page => params[:page], :per_page => 30)
    # TODO: Fix this mess
    if params['my_projects']
      @proficient_projects = @proficient_projects.where(id: current_user.order_items.completed_order.pluck(:proficient_project_id))
    else
      @proficient_projects = @proficient_projects.where.not(id: current_user.order_items.completed_order.pluck(:proficient_project_id))
    end
    @training_levels = TrainingSession.return_levels
    @training_categories_names = Training.all.order('name ASC').pluck(:name)
    @order_item = current_order.order_items.new
    @user_order_items = current_user.order_items.completed_order
  end

  def new
    @proficient_project = ProficientProject.new
    @training_levels ||= TrainingSession.return_levels
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
      @proficient_project.create_badge_requirements(params[:badge_requirements_id]) if params[:badge_requirements_id].present?
      create_photos
      create_files
      flash[:notice] = "Proficient Project successfully created."
      render json: {redirect_uri: "#{proficient_project_path(@proficient_project.id)}"}
    else
      flash[:alert] = "Something went wrong"
      render json: @proficient_project.errors["title"].first, status: :unprocessable_entity
    end
  end

  def destroy
    @proficient_project.destroy
    respond_to do |format|
      format.html { redirect_to proficient_projects_path(proficiency: true), notice: 'Proficient Project has been successfully deleted.' }
      format.json { head :no_content }
    end
  end

  def edit
    @training_levels = TrainingSession.return_levels
  end

  def update
    @proficient_project.delete_all_badge_requirements
    @proficient_project.create_badge_requirements(params[:badge_requirements_id]) if params[:badge_requirements_id].present?

    if @proficient_project.update(proficient_project_params)
      update_photos
      update_files
      update_videos
      flash[:notice] = "Proficient Project successfully updated."
      render json: {redirect_uri: "#{proficient_project_path(@proficient_project.id)}"}
    else
      flash[:alert] = "Unable to apply the changes."
      render json: @proficient_project.errors["title"].first, status: :unprocessable_entity
    end
  end

  def open_modal
    @proficient_project_modal = ProficientProject.find(params[:id])
    @order_item = current_order.order_items.new
    @user_order_items = current_user.order_items.completed_order
    respond_to do |format|
      format.js
    end
  end

  private

    def grant_access_to_project
      unless current_user.order_items.completed_order.where(proficient_project: @proficient_project, status: ["Awarded", "In progress"]).present?
        unless current_user.admin? || current_user.staff?
          redirect_to development_programs_path
          flash[:alert] = "You cannot access this area."
        end
      end
    end

    def only_admin_access
      unless current_user.admin?
        redirect_to development_programs_path
        flash[:alert] = "Only admin members can access this area."
      end
    end

    def proficient_project_params
      params.require(:proficient_project).permit(:title, :description, :training_id, :level, :proficient, :cc, :badge_template_id)
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

    def set_proficient_project
      @proficient_project = ProficientProject.find(params[:id])
    end

    def set_training_categories
      @training_categories = Training.all.order(:name).pluck(:name, :id)
    end

    def set_files_photos_videos
      @photos = @proficient_project.photos || []
      @files = @proficient_project.repo_files.order(created_at: :asc)
      @videos = @proficient_project.videos.processed.order(created_at: :asc)
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
    end

    def get_filter_params
      params.permit(:search, :level, :category, :proficiency, :my_projects)
    end

    def set_badge_templates
      @badge_templates = BadgeTemplate.all.order(badge_name: :asc)
    end

end
