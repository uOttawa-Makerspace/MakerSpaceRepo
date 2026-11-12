# frozen_string_literal: true

class ProficientProjectsController < DevelopmentProgramsController
  before_action :only_admin_access,
                only: %i[
                  new
                  create
                  edit
                  update
                  destroy
                ]
  before_action :only_staff_access,
                only: %i[
                  requests
                  approve_project
                  revoke_project
  ]
  before_action :set_proficient_project,
                only: %i[show destroy edit update complete_project]
  before_action :grant_access_to_project, only: [:show]
  before_action :set_training_categories,
                :set_drop_off_location,
                only: %i[new edit]
  before_action :set_files_photos_videos, only: %i[show edit]
  before_action :with_development_header

  def index
    @skills = Skill.includes(:trainings)
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
    case save_new_project
    when :created
      create_files
      redirect_to proficient_project_path(@proficient_project.id),
                  notice: "Proficient Project successfully created."
    when :refused
      redirect_to request.path, alert: @photo_refusal
    else
      @training_levels ||= TrainingSession.return_levels
      @training_categories = Training.all.order(:name_en).pluck(:name_en, :id)
      @drop_off_location = DropOffLocation.all.order(name: :asc)
      @trainings = Training.all
      flash[:alert] = validation_message(@proficient_project, "errors.shop.projects.create_invalid")
      render "new", status: :unprocessable_content
    end
  end

  def destroy
    if @proficient_project.destroy
      respond_to do |format|
        format.html do
          redirect_to proficient_projects_path,
                      notice: "Proficient Project has been successfully deleted."
        end
        format.json { head :no_content }
      end
    else
      respond_to do |format|
        format.html do
          redirect_to proficient_project_path(@proficient_project),
                      alert: validation_message(@proficient_project, "errors.shop.projects.not_deleted")
        end
        format.json { render json: { errors: @proficient_project.errors.full_messages }, status: :unprocessable_content }
      end
    end
  end

  def edit
    @training_levels = TrainingSession.return_levels
    @trainings = Training.all
    @training_requirements = TrainingRequirement.all.where(proficient_project_id: @proficient_project.id)
  end

  def update
    case save_project_changes
    when :updated
      flash[:notice] = "Proficient Project successfully updated."
      redirect_to proficient_project_path(@proficient_project.id)
    when :refused
      redirect_to edit_proficient_project_path(@proficient_project), alert: @photo_refusal
    else
      flash[:alert] = validation_message(@proficient_project, "errors.shop.projects.update_invalid")
      @training_categories = Training.all.order(:name_en).pluck(:name_en, :id)
      @training_levels = TrainingSession.return_levels
      @trainings = Training.all
      @drop_off_location = DropOffLocation.all.order(name: :asc)
      @photos = @proficient_project.photos || []
      @files = @proficient_project.repo_files.order(created_at: :asc)
      @videos = @proficient_project.videos.processed.order(created_at: :asc)
      render "edit", status: :unprocessable_content
    end
  end

  def proficient_project_modal
    @proficient_project = ProficientProject.find(params[:proficient_project_id])
    render layout: false
  end

  def complete_project
    order_items =
      current_user.order_items.completed_order.where(
        proficient_project_id: @proficient_project.id
      )
    if !order_items.present?
      flash[:alert] = I18n.t("errors.shop.projects.not_found")
    elsif !order_items.in_progress.exists?
      flash[:alert] = I18n.t("errors.shop.projects.not_in_progress")
    elsif (submission = order_items.in_progress.first).update(
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
      flash[:alert] = validation_message(submission, "errors.shop.projects.submit_invalid")
    end
    redirect_to @proficient_project
  end

  def approve_project
    order_item = OrderItem.find_by(id: params[:oi_id])
    if order_item.nil?
      flash[:error] = I18n.t("errors.shop.projects.submission_not_found")
    else
      award(order_item)
    end
    redirect_to(order_item.nil? || current_user.admin? ? requests_proficient_projects_path : order_item.proficient_project)
  end

  def revoke_project
    order_item = OrderItem.find_by(id: params[:oi_id])
    if order_item.nil?
      flash[:error] = I18n.t("errors.shop.projects.submission_not_found")
    else
      revoke(order_item)
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
      redirect_to proficient_projects_path
      # flash[:alert] = "Only admin members can access this area."
  end

  def only_staff_access
    return if current_user.staff?
      redirect_to development_programs_path
      flash[:alert] = "Only staff members can access this area."
  end

  def proficient_project_params
    params.require(:proficient_project).permit(
      :title,
      :description,
      :training_id,
      :level,
      :cc,
      :has_project_kit,
      :drop_off_location_id,
      :is_virtual
    )
  end

  def training_requirement_params
    params.require(:training_requirements).permit(
      :training_requirements_id,
      :training_requirements_level
    )
  end

  def order_item_params
    params.require(:order_item).permit(
      :user_comments,
      :admin_comments,
      files: []
    )
  end

  # Awards the badge for a submission waiting for approval, then mails the result. A submission in
  # any other state, or one that fails validation, awards nothing and says which.
  def award(order_item)
    case (result = award_result(order_item))
    when :awarded
      MsrMailer.send_results_pp(order_item, order_item.order.user, "Passed").deliver_now
      flash[:notice] = "The project has been approved!"
    when :not_waiting
      flash[:error] = I18n.t("errors.shop.projects.not_waiting")
    else
      flash[:error] = validation_message(result.record, "errors.shop.projects.approve_invalid")
    end
  end

  # :awarded, :not_waiting, or the RecordInvalid / RecordNotSaved that rolled the award back.
  def award_result(order_item)
    order_item.award!(@user, order_item_params) ? :awarded : :not_waiting
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
    e
  end

  # Revokes a submission waiting for approval, then mails the result.
  def revoke(order_item)
    revoked = nil
    order_item.with_lock do
      revoked = order_item.update(order_item_params.merge(status: "Revoked")) if order_item.status == "Waiting for approval"
    end
    if revoked
      MsrMailer.send_results_pp(order_item, order_item.order.user, "Failed").deliver_now
      flash[:alert_yellow] = "The project has been revoked."
    elsif revoked.nil?
      flash[:error] = I18n.t("errors.shop.projects.not_waiting")
    else
      flash[:error] = validation_message(order_item, "errors.shop.projects.revoke_invalid")
    end
  end

  # Saves the new project with its requirements and photos in one transaction: :created,
  # :invalid (the project failed validation) or :refused (a photo was refused, so nothing is
  # stored; the reason is in @photo_refusal).
  def save_new_project
    ProficientProject.transaction do
      if @proficient_project.save
        create_training_requirements
        create_photos
        :created
      else
        :invalid
      end
    end
  rescue Photo::Refused => e
    @photo_refusal = "#{I18n.t('errors.shop.projects.photos_refused_on_create')} #{e.message}"
    :refused
  end

  def create_training_requirements
    Array(params[:training_requirements_id]).each_with_index do |t, i|
      @proficient_project.create_training_requirements(t, params[:training_requirements_level][i])
    end
  end

  def create_photos
    Photo.create_from_uploads!(Array(params["images"]), proficient_project_id: @proficient_project.id)
  end

  # Saves the edit with its requirements and media in one transaction: :updated, :invalid (the
  # project failed validation, so nothing is saved) or :refused as for a new project.
  def save_project_changes
    outcome = :invalid
    ProficientProject.transaction do
      replace_training_requirements
      raise ActiveRecord::Rollback unless @proficient_project.update(proficient_project_params)

      update_media
      outcome = :updated
    end
    outcome
  rescue Photo::Refused => e
    @photo_refusal = "#{I18n.t('errors.shop.projects.photos_refused_on_update')} #{e.message}"
    :refused
  end

  def create_files
    return unless params["files"].present?
      params["files"].each do |f|
        @repo =
          RepoFile.new(file: f, proficient_project_id: @proficient_project.id)
        flash[:alert] = I18n.t("errors.shop.projects.files_not_pdf") unless @repo.save
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

  # The edit form always lists the project's whole requirement set; a request that
  # carries neither the list nor the form marker leaves the requirements alone.
  def replace_training_requirements
    return unless params[:training_requirements_id].present? || params[:training_requirements_managed].present?
    @proficient_project.replace_training_requirements(
      params[:training_requirements_id],
      params[:training_requirements_level]
    )
  end

  def update_media
    update_photos
    update_files
    update_videos
  end

  # New photos are added before any ticked one is removed, so a refused photo leaves the existing
  # photos untouched. Removing a record deletes only its row here; Active Storage deletes the
  # stored file after the surrounding transaction has committed, so a failed save keeps the files.
  def update_photos
    create_photos
    @proficient_project.photos.where(id: ticked_ids("deleteimages")).find_each(&:destroy)
  end

  def update_files
    ticked = ticked_ids("deletefiles")
    @proficient_project.repo_files.where(id: ticked).find_each(&:destroy)

    Array(params["files"]).each do |f|
      repo = RepoFile.new(file: f, proficient_project_id: @proficient_project.id)
      next if repo.save
      flash[
        :alert
      ] = "Make sure you only upload PDFs for the project files, the PDFs were uploaded"
    end
  end

  def update_videos
    ticked = ticked_ids("deletevideos")
    return if ticked.empty?

    @proficient_project.videos.each do |f|
      removed = f.video.attachments.where(id: ticked).each(&:destroy)
      f.destroy if removed.any? && !f.reload.video.attached?
    end
  end

  # Record ids ticked for removal on the edit form: a comma-joined string (or a list).
  def ticked_ids(name)
    Array(params[name]).flat_map { |v| v.to_s.split(",") }.map(&:strip).reject(&:blank?).map(&:to_i)
  end

  def get_filter_params
    params.permit(:search, :level, :category, :my_projects, :price)
  end

  def set_drop_off_location
    @drop_off_location = DropOffLocation.all.order(name: :asc)
  end
end
