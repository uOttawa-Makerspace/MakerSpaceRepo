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
                :set_badge_templates,
                :set_drop_off_location,
                only: %i[new edit]
  before_action :set_files_photos_videos, only: %i[show edit]

  def index
    @skills = Skill.all
    @proficient_projects_awarded =
      Proc.new do |training|
        training.proficient_projects.where(
          id: current_user.order_items.awarded.pluck(:proficient_project_id)
        )
      end
    @all_proficient_projects =
      Proc.new { |training| training.proficient_projects }
    @advanced_pp_count =
      Proc.new do |training|
        training.proficient_projects.where(level: "Advanced").count
      end
    @order_item = current_order.order_items.new
    @user_order_items = current_user.order_items.completed_order
    @proficient_projects_bought =
      Proc.new do |training|
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
    @order_item_waiting_for_approval = OrderItem.all.waiting_for_approval
  end

  def new
    @proficient_project = ProficientProject.new
    @training_levels ||= TrainingSession.return_levels
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
    badge_template_id =
      BadgeTemplate.where(
        training_id: params[:proficient_project][:training_id],
        training_level: params[:proficient_project][:level]
      ).first
    if badge_template_id.present?
      (params[:proficient_project][:badge_template_id] = badge_template_id.id)
    else
      (params[:proficient_project][:badge_template_id] = nil)
    end
    @proficient_project = ProficientProject.new(proficient_project_params)
    if @proficient_project.save
      if params[:badge_requirements_id].present?
        @proficient_project.create_badge_requirements(
          params[:badge_requirements_id]
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
      @training_categories = Training.all.order(:name).pluck(:name, :id)
      @drop_off_location = DropOffLocation.all.order(name: :asc)
      @badge_templates = BadgeTemplate.all.order(badge_name: :asc)
      flash[:alert] = "Something went wrong"
      render "new", status: 422
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
  end

  def update
    @proficient_project.delete_all_badge_requirements
    if params[:badge_requirements_id].present?
      @proficient_project.create_badge_requirements(
        params[:badge_requirements_id]
      )
    end

    badge_template_id =
      BadgeTemplate.where(
        training_id: params[:proficient_project][:training_id],
        training_level: params[:proficient_project][:level]
      ).first
    if badge_template_id.present?
      (params[:proficient_project][:badge_template_id] = badge_template_id.id)
    else
      (params[:proficient_project][:badge_template_id] = nil)
    end

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
      render "edit", status: 422
    end
  end

  def open_modal
    @proficient_project_modal = ProficientProject.find(params[:id])
    @order_item = current_order.order_items.new
    @user_order_items = current_user.order_items.completed_order
    respond_to { |format| format.js }
  end

  def complete_project
    order_items =
      current_user.order_items.where(
        proficient_project_id: @proficient_project.id
      )
    if !order_items.present?
      flash[:alert] = "This project hasn't been found"
    elsif !order_items.first.update(
          order_item_params.merge(status: "Waiting for approval")
        )
      msg = "The project didn't update<br>"
      if order_items.first.errors.any?
        order_items.first.errors.full_messages.each do |message|
          msg += message + "<br>"
        end
      end
      flash[:alert] = msg.html_safe
    else
      MsrMailer.send_admin_pp_evaluation(@proficient_project).deliver_now
      MsrMailer.send_user_pp_evaluation(
        @proficient_project,
        current_user
      ).deliver_now
      flash[
        :notice
      ] = "Congratulations on submitting this proficient project! The proficient project will now be reviewed by an admin in around 5 business days."
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
      training_session =
        TrainingSession.find_or_create_by(
          training_id: order_item.proficient_project.training_id,
          level: order_item.proficient_project.level,
          user: admin,
          space: space,
          course_name: course_name
        )
      training_session.users << order_item.order.user
      if training_session.present?
        cert =
          Certification.find_or_create_by(
            training_session_id: training_session.id,
            user_id: order_item.order.user_id
          )
        badge_template = order_item.proficient_project.badge_template
        if badge_template.present?
          user = order_item.order.user
          response =
            Badge.acclaim_api_create_badge(
              user,
              badge_template.acclaim_template_id
            )
          if response.status == 201
            badge_data = JSON.parse(response.body)["data"]
            Badge.create(
              user_id: user.id,
              issued_to: user.name,
              acclaim_badge_id: badge_data["id"],
              badge_template_id: badge_template.id,
              certification: cert
            )
            order_item.update(status: "Awarded")
            MsrMailer.send_results_pp(
              order_item.proficient_project,
              order_item.order.user,
              "Passed"
            ).deliver_now
            flash[:notice] = "A badge has been awarded to the user!"
          else
            flash[
              :alert
            ] = "An error has occurred when creating the badge, this message might help : " +
              JSON.parse(response.body)["data"]["message"]
          end
        else
          order_item.update(status: "Awarded")
          MsrMailer.send_results_pp(
            order_item.proficient_project,
            order_item.order.user,
            "Passed"
          ).deliver_now
        end
        flash[:notice] = "The project has been approved!"
      else
        flash[:error] = "An error has occurred, please try again later."
      end
    else
      flash[:error] = "An error has occurred, please try again later."
    end
    current_user.admin? ?
      redirect_path = requests_proficient_projects_path :
      redirect_path = order_item.proficient_project
    redirect_to redirect_path
  end

  def revoke_project
    order_item = OrderItem.find_by(id: params[:oi_id])
    if order_item
      order_item.update(status: "Revoked")
      MsrMailer.send_results_pp(
        order_item.proficient_project,
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
      BadgeTemplate.where(
        training_id: params[:training_id],
        training_level: params[:level]
      ).first
    if badge.present?
      render plain: "#{badge.badge_name}"
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
         .blank?
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
    params.require(:proficient_project).permit(
      :title,
      :description,
      :training_id,
      :level,
      :proficient,
      :cc,
      :badge_template_id,
      :has_project_kit,
      :drop_off_location_id,
      :is_virtual
    )
  end

  def order_item_params
    params.require(:order_item).permit(:comments, files: [])
  end

  def create_photos
    if params["images"].present?
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
  end

  def create_files
    if params["files"].present?
      params["files"].each do |f|
        @repo =
          RepoFile.new(file: f, proficient_project_id: @proficient_project.id)
        unless @repo.save
          flash[:alert] = "Make sure you only upload PDFs for the project files"
        end
      end
    end
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
    if params["deleteimages"].present?
      @proficient_project.photos.each do |img|
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
          proficient_project_id: @proficient_project.id,
          width: dimension.first,
          height: dimension.last
        )
      end
    end
  end

  def update_files
    if params["deletefiles"].present?
      @proficient_project.repo_files.each do |f|
        if params["deletefiles"].include?(f.file.filename.to_s)
          # checks if the file should be deleted
          f.file.purge
          f.destroy
        end
      end
    end

    if params["files"].present?
      params["files"].each do |f|
        repo =
          RepoFile.new(file: f, proficient_project_id: @proficient_project.id)
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
      @proficient_project.videos.each do |f|
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
    params.permit(:search, :level, :category, :my_projects, :price)
  end

  def set_badge_templates
    @badge_templates = BadgeTemplate.all.order(badge_name: :asc)
  end

  def set_drop_off_location
    @drop_off_location = DropOffLocation.all.order(name: :asc)
  end
end
