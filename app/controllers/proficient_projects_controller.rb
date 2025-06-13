# frozen_string_literal: true

class ProficientProjectsController < DevelopmentProgramsController
  before_action :only_admin_access,
                only: %i[
                  new
                  create
                  edit
                  update
                  destroy
                  requests
                  approve_project
                ]
  before_action :set_proficient_project,
                only: %i[show destroy edit update complete_project]
  before_action :grant_access_to_project, only: [:show]
  before_action :set_training_categories,
                :set_drop_off_location,
                only: %i[new edit]
  before_action :set_files_photos_videos, only: %i[show edit]

  def index
    @skills = Skill.all
    @proficient_projects_awarded =
      proc do |training|
        training.proficient_projects.where(
          id: current_user.order_items.awarded.pluck(:proficient_project_id)
        )
      end
    @all_proficient_projects =
      proc { |training| training.proficient_projects }
    @advanced_pp_count =
      proc do |training|
        training.proficient_projects.where(level: "Advanced").count
      end
    @order_item = current_order.order_items.new
    @user_order_items = current_user.order_items.completed_order
    @proficient_projects_bought =
      proc do |training|
        training.proficient_projects.where(
          id:
            current_user
              .order_items
              .where(status: ["Awarded", "In progress", "Waiting for approval"])
              .pluck(:proficient_project_id)
        )
      end
  end

  def requests
    @order_item_waiting_for_approval =
      OrderItem.all.waiting_for_approval.order(updated_at: :asc)
  end

  def new
    @proficient_project = ProficientProject.new
    @training_levels ||= TrainingSession.return_levels
    @trainings = Training.all
  end

  def show
    @project_requirements = @proficient_project.project_requirements
    @inverse_required_projects = @proficient_project.inverse_required_projects
    @proficient_projects_selected =
      ProficientProject
        .where.not(
          id:
            @project_requirements.pluck(
              :required_project_id
            ) << @proficient_project.id
        )
        .order(title: :asc)
    @valid_urls = @proficient_project.extract_valid_urls
    @order_item =
      current_user
        .order_items
        .where(proficient_project: @proficient_project)
        .order(updated_at: :desc)
        .first
  end

  def create
    @proficient_project = ProficientProject.new(proficient_project_params)
    if @proficient_project.save
      if params[:training_requirements_id].present?
        @proficient_project.create_training_requirements(
          params[:training_requirements_id]
        )
      end
      begin
        create_photos
      rescue FastImage::ImageFetchFailure,
             FastImage::UnknownImageType,
             FastImage::SizeNotFound => e
        @proficient_project.destroy
        redirect_to request.path,
                    alert:
                      "Something went wrong while uploading photos, try uploading them again later."
      else
        create_files
        redirect_to proficient_project_path(@proficient_project.id),
                    notice: "Proficient Project successfully created."
      end
    else
      @training_levels ||= TrainingSession.return_levels
      @training_categories = Training.all.order(:name_en).pluck(:name_en, :id)
      @drop_off_location = DropOffLocation.all.order(name: :asc)
      flash[:alert] = "Something went wrong"
      render "new", status: :unprocessable_entity
    end
  end

  def destroy
    @proficient_project.destroy
    respond_to do |format|
      format.html do
        redirect_to proficient_projects_path,
                    notice: "Proficient Project has been successfully deleted."
      end
      format.json { head :no_content }
    end
  end

  def edit
    @training_levels = TrainingSession.return_levels
    @trainings = Training.all
  end

  def update
    if @proficient_project.update(proficient_project_params)
      update_files
      update_videos
      begin
        update_photos
      rescue FastImage::ImageFetchFailure,
             FastImage::UnknownImageType,
             FastImage::SizeNotFound => e
        flash[
          :alert_yellow
        ] = "Something went wrong while uploading photos, try again later. Other changes have been saved."
        redirect_to proficient_project_path(@proficient_project.id)
      else
        flash[:notice] = "Proficient Project successfully updated."
        redirect_to proficient_project_path(@proficient_project.id)
      end
    else
      flash[:alert] = "Unable to apply the changes."
      render "edit", status: :unprocessable_entity
    end
  end

  def open_modal
    @proficient_project_modal = ProficientProject.find(params[:id])
    @order_item = current_order.order_items.new
    @user_order_items = current_user.order_items.completed_order
    respond_to { |format| format.js }
  end

  def proficient_project_modal
    @proficient_project = ProficientProject.find(params[:proficient_project_id])
    render layout: false
  end

  def complete_project
    order_items =
      current_user.order_items.where(
        proficient_project_id: @proficient_project.id
      )
    if !order_items.present?
      flash[:alert] = "This project hasn't been found"
    elsif order_items.first.update(
          order_item_params.merge(status: "Waiting for approval")
        )
      MsrMailer.send_admin_pp_evaluation(@proficient_project).deliver_now
      MsrMailer.send_user_pp_evaluation(
        @proficient_project,
        current_user
      ).deliver_now
      flash[
        :notice
      ] = "Congratulations on submitting this proficient project! The proficient project will now be reviewed by an admin in around 5 business days."
    else
      flash[
        :alert
      ] = "Something went wrong with updating the proficient project. Please check the allowed file types."
    end
    redirect_to @proficient_project
  end

  def approve_project
    order_item = OrderItem.find_by(id: params[:oi_id])
    if order_item
      space = Space.find_by_name("Makerepo")
      admin =
        User.find_by_email("avend029@uottawa.ca") ||
          User.where(role: "admin").last
      course_name = CourseName.find_by_name("no course")
      proficient_project_session =
        ProficientProjectSession.create(
          proficient_project_id: order_item.proficient_project.id,
          level: order_item.proficient_project.level,

        )
      # Make sure we don't double add the HABTM relation
      # In case badge fails somehow, at least we award the skill
      if proficient_project_session.present?
        cert =
          Certification.create(
            user_id: order_item.order.user_id,
            level: proficient_project_session.level
          )
        # Award project, even if badge fails.
        # You can manually grant badge later
        order_item.update(order_item_params.merge({ status: "Awarded" }))
        MsrMailer.send_results_pp(
          order_item,
          order_item.order.user,
          "Passed"
        ).deliver_now
        flash[:notice] = "The project has been approved!"
      else
        flash[:error] = "An error has occurred, please try again later."
      end
    else
      flash[:error] = "An error has occurred, please try again later."
    end
    redirect_path = current_user.admin? ? requests_proficient_projects_path : order_item.proficient_project
    redirect_to redirect_path
  end

  def revoke_project
    order_item = OrderItem.find_by(id: params[:oi_id])
    if order_item
      order_item.update(order_item_params.merge(status: "Revoked"))
      MsrMailer.send_results_pp(
        order_item,
        order_item.order.user,
        "Failed"
      ).deliver_now
      flash[:alert_yellow] = "The project has been revoked."
    else
      flash[:error] = "An error has occurred, please try again later."
    end
    redirect_to requests_proficient_projects_path
  end

  def generate_acquired_badge
    badge =
      Training.where(
        id: params[:training_id],
      ).first
    if badge.present?
      render plain: "#{badge.name_en} - #{params[:level]}"
    else
      render plain: "No badges will be acquired"
    end
  end

  private

  def grant_access_to_project
    if current_user
         .order_items
         .completed_order
         .where(
           proficient_project: @proficient_project,
           status: ["Awarded", "In progress", "Waiting for approval"]
         )
         .blank? && !(current_user.admin? || current_user.staff?)
        redirect_to development_programs_path
        flash[:alert] = "You cannot access this area."
      end
  end

  def only_admin_access
    return if current_user.admin?
      redirect_to development_programs_path
      flash[:alert] = "Only admin members can access this area."
    
  end

  def proficient_project_params
    params.require(:proficient_project).permit(
      :title,
      :description,
      :training_id,
      :level,
      :proficient,
      :cc,
      :has_project_kit,
      :drop_off_location_id,
      :is_virtual
    )
  end

  def order_item_params
    params.require(:order_item).permit(
      :user_comments,
      :admin_comments,
      files: []
    )
  end

  def create_photos
    return unless params["images"].present?
      params["images"].each do |img|
        dimension = FastImage.size(img.tempfile, raise_on_failure: true)
        Photo.create(
          image: img,
          proficient_project_id: @proficient_project.id,
          width: dimension.first,
          height: dimension.last
        )
      end
    
  end

  def create_files
    return unless params["files"].present?
      params["files"].each do |f|
        @repo =
          RepoFile.new(file: f, proficient_project_id: @proficient_project.id)
        flash[:alert] = "Make sure you only upload PDFs for the project files" unless @repo.save
      end
    
  end

  def set_proficient_project
    @proficient_project = ProficientProject.find(params[:id])
  end

  def set_training_categories
    @training_categories = Training.all.order(:name_en).pluck(:name_en, :id)
  end

  def set_files_photos_videos
    @photos = @proficient_project.photos || []
    @files = @proficient_project.repo_files.order(created_at: :asc)
    @videos = @proficient_project.videos.processed.order(created_at: :asc)
  end

  def update_photos
    if params["deleteimages"].present?
      @proficient_project.photos.each do |img|
        next unless params["deleteimages"].include?(img.image.filename.to_s)
        # checks if the file should be deleted
        img.image.purge
        img.destroy
      end
    end

    return unless params["images"].present?
      params["images"].each do |img|
        dimension = FastImage.size(img.tempfile, raise_on_failure: true)
        Photo.create(
          image: img,
          proficient_project_id: @proficient_project.id,
          width: dimension.first,
          height: dimension.last
        )
      end
    
  end

  def update_files
    if params["deletefiles"].present?
      @proficient_project.repo_files.each do |f|
        next unless params["deletefiles"].include?(f.file.filename.to_s)
        # checks if the file should be deleted
        f.file.purge
        f.destroy
      end
    end

    return unless params["files"].present?
      params["files"].each do |f|
        repo =
          RepoFile.new(file: f, proficient_project_id: @proficient_project.id)
        next if repo.save
        flash[
          :alert
        ] = "Make sure you only upload PDFs for the project files, the PDFs were uploaded"
      end
    
  end

  def update_videos
    videos_id = params["deletevideos"]
    return unless videos_id.present?
      videos_id = videos_id.split(",").uniq.map { |id| id.to_i }
      @proficient_project.videos.each do |f|
        next unless (f.video.pluck(:id) & videos_id).any?
        videos_id.each do |video_id|
          video = f.video.find(video_id)
          video.purge
        end
        f.destroy unless f.video.attached?
      end
    
  end

  def get_filter_params
    params.permit(:search, :level, :category, :my_projects, :price)
  end

  def set_drop_off_location
    @drop_off_location = DropOffLocation.all.order(name: :asc)
  end
end
