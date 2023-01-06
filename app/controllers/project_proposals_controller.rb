# frozen_string_literal: true

class ProjectProposalsController < ApplicationController
  before_action :set_project_proposal, only: %i[show edit update destroy]
  before_action :current_user
  before_action :show_only_project_approved, only: [:show]

  # GET /project_proposals
  # GET /project_proposals.json
  def index
    if params[:search].blank?
      @pending_project_proposals =
        ProjectProposal
          .all
          .joins(:user)
          .order(created_at: :desc)
          .where(approved: nil)
          .paginate(per_page: 15, page: params[:page_pending])
      @approved_project_proposals =
        ProjectProposal
          .all
          .joins(:user)
          .order(created_at: :desc)
          .where(approved: 1)
          .paginate(per_page: 15, page: params[:page_approved])
      @not_approved_project_proposals =
        ProjectProposal
          .all
          .joins(:user)
          .order(created_at: :desc)
          .where(approved: 0)
          .paginate(per_page: 15, page: params[:page_not_approved])
    else
      @pending_project_proposals =
        ProjectProposal
          .all
          .joins(:user)
          .filter_by_attribute(params[:search])
          .order(created_at: :desc)
          .where(approved: nil)
          .paginate(per_page: 15, page: params[:page_pending])
      @approved_project_proposals =
        ProjectProposal
          .all
          .joins(:user)
          .filter_by_attribute(params[:search])
          .order(created_at: :desc)
          .where(approved: 1)
          .paginate(per_page: 15, page: params[:page_approved])
      @not_approved_project_proposals =
        ProjectProposal
          .all
          .joins(:user)
          .filter_by_attribute(params[:search])
          .order(created_at: :desc)
          .where(approved: 0)
          .paginate(per_page: 15, page: params[:page_not_approved])
    end
    respond_to do |format|
      format.js
      format.html
    end
  end

  def user_projects
    @project_proposals_joined =
      ProjectProposal
        .all
        .joins(:project_joins)
        .where(project_joins: { user: current_user })
        .order(created_at: :desc)
        .paginate(per_page: 15, page: params[:page])
    @user_pending_project_proposals =
      current_user
        .project_proposals
        .where(approved: nil)
        .order(created_at: :desc)
        .paginate(per_page: 15, page: params[:page])
    @approved_project_proposals =
      current_user
        .project_proposals
        .order(created_at: :desc)
        .where(approved: 1)
        .paginate(per_page: 15, page: params[:page_approved])
  end

  # GET /project_proposals/1
  # GET /project_proposals/1.json
  def show
    @categories = @project_proposal.categories
    @repositories =
      @project_proposal.repositories.order([sort_order].to_h).page params[:page]
    @photos = photo_hash
    @project_photos =
      @project_proposal.photos.joins(:image_attachment)&.first(5) || []
    @project_files = @project_proposal.repo_files.joins(:file_attachment)
    @linked_pp = @project_proposal.linked_project_proposal
    @revisions =
      ProjectProposal.where(linked_project_proposal_id: @project_proposal.id)
  end

  # GET /project_proposals/new
  def new
    @project_proposal = ProjectProposal.new
  end

  # GET /project_proposals/1/edit
  def edit
    @categories = @project_proposal.categories
    @category_options = CategoryOption.show_options
    @photos = @project_proposal.photos.joins(:image_attachment).first(5)
    @files = @project_proposal.repo_files.joins(:file_attachment)
  end

  def projects_assigned
    @assigned_project_proposals =
      ProjectProposal
        .joins(:project_joins)
        .joins(
          "LEFT OUTER JOIN repositories ON (project_proposals.id = repositories.project_proposal_id)"
        )
        .where("repositories.id IS NULL")
        .where(approved: 1)
        .distinct
        .order(created_at: :desc)
        .paginate(per_page: 15, page: params[:page])
  end

  def projects_completed
    @completed_project_proposals =
      ProjectProposal
        .where(approved: 1)
        .joins(:repositories)
        .distinct
        .order(created_at: :desc)
        .paginate(per_page: 15, page: params[:page])
  end

  # POST /project_proposals
  # POST /project_proposals.json
  def create
    @project_proposal =
      ProjectProposal.new(project_proposal_params.except(:categories))
    @project_proposal.user_id = @user.try(:id)

    respond_to do |format|
      if @project_proposal.save
        begin
          create_photos
        rescue FastImage::ImageFetchFailure,
               FastImage::UnknownImageType,
               FastImage::SizeNotFound => e
          Airbrake.notify(e)
          flash[
            :alert
          ] = "Something went wrong while uploading photos, try again later."
          @project_proposal.destroy
          format.json { render json: { redirect_uri: request.path } }
          format.html { redirect_back fallback_location: request.path }
        else
          create_files
          create_categories
          @project_proposal.save # This creates the slug with ID since the ID is not created before create
          format.html do
            redirect_to project_proposal_path(@project_proposal.slug),
                        notice: "Project proposal was successfully created."
          end
          format.json do
            render json: {
                     redirect_uri:
                       project_proposal_path(@project_proposal.slug).to_s
                   }
          end
          MsrMailer.send_new_project_proposals.deliver_now
        end
      else
        flash[
          :alert
        ] = "An error occurred while creating the project proposal, try again later."
        format.html { render :new, status: :unprocessable_entity }
        format.json do
          render json: @project_proposal.errors, status: :unprocessable_entity
        end
      end
    end
  end

  def create_revision
    if params[:old_project_proposal_id] &&
         ProjectProposal.where(id: params[:old_project_proposal_id]).present?
      @old_project_proposal =
        ProjectProposal.find(params[:old_project_proposal_id])
      values =
        @old_project_proposal.attributes.except(
          "id",
          "user_id",
          "admin_id",
          "approved",
          "slug"
        )
      values["title"] = "Revision of #{values["title"]}"
      values["linked_project_proposal_id"] = params[:old_project_proposal_id]

      @project_proposal = ProjectProposal.new(values)
      @project_proposal.user_id = @user.try(:id)
      @project_proposal.save!

      if @old_project_proposal.photos.present? &&
           @old_project_proposal.photos.first.image.attached?
        @old_project_proposal.photos.each do |photo|
          Photo.create(
            project_proposal_id: @project_proposal.id,
            width: photo.width,
            height: photo.height
          )
          photo.image.blob.open do |temp_photo|
            Photo.last.image.attach(
              {
                io: temp_photo,
                filename: photo.image.blob.filename,
                content_type: photo.image.blob.content_type
              }
            )
          end
        end
      end

      if @old_project_proposal.repo_files.present? &&
           @old_project_proposal.repo_files.first.file.attached?
        @old_project_proposal.repo_files.each do |file|
          RepoFile.create(project_proposal_id: @project_proposal.id)
          file.file.blob.open do |temp_file|
            RepoFile.last.file.attach(
              {
                io: temp_file,
                filename: file.file.blob.filename,
                content_type: file.file.blob.content_type
              }
            )
          end
        end
      end

      @old_project_proposal.categories.each do |category|
        Category.create(
          name: category.name,
          project_proposal_id: @project_proposal.id
        )
      end

      respond_to do |format|
        if @project_proposal.save!
          # This creates the slug with ID since the ID is not created before create
          format.html do
            redirect_to project_proposal_path(@project_proposal.slug),
                        notice:
                          "The project proposal revision has been successfully created."
          end
          format.json do
            render json: {
                     redirect_uri:
                       project_proposal_path(@project_proposal.slug).to_s
                   }
          end
        else
          format.html do
            redirect_to project_proposal_path(@old_project_proposal.slug),
                        alert:
                          "An error occured while creating the Project proposal revision, please try again later."
          end
        end
      end
    else
      redirect_back(
        fallback_location: root_path,
        alert:
          "An error occured while trying to create a project proposal revision, please try again later."
      )
    end
  end

  # PATCH/PUT /project_proposals/1
  # PATCH/PUT /project_proposals/1.json
  def update
    @project_proposal.categories.destroy_all
    respond_to do |format|
      if @project_proposal.update(project_proposal_params.except(:categories))
        update_files
        create_categories
        begin
          update_photos
        rescue FastImage::ImageFetchFailure,
               FastImage::UnknownImageType,
               FastImage::SizeNotFound => e
          Airbrake.notify(e)
          flash[
            :alert_yellow
          ] = "Something went wrong while uploading photos, try again later. Other changes have been saved. "
          format.json { render json: { redirect_uri: request.path } }
          format.html { redirect_back fallback_location: request.path }
        else
          format.html do
            redirect_to project_proposal_path(@project_proposal.slug),
                        notice: "Project proposal was successfully updated."
          end
          format.json do
            render json: {
                     redirect_uri:
                       project_proposal_path(@project_proposal.slug).to_s
                   }
          end
        end
      else
        flash[
          :alert
        ] = "An error occurred while updating the project proposal, try again later."
        format.html { render :edit, status: :unprocessable_entity }
        format.json do
          render json: @project_proposal.errors, status: :unprocessable_entity
        end
      end
    end
  end

  # DELETE /project_proposals/1
  # DELETE /project_proposals/1.json
  def destroy
    return unless current_user.admin?
    @project_proposal.destroy
    respond_to do |format|
      format.html do
        redirect_to project_proposals_url,
                    notice: "Project proposal was successfully deleted."
      end
      format.json { head :no_content }
    end
  end

  def approve
    @project_proposal = ProjectProposal.find(params[:id])
    @project_proposal.update(approved: 1, admin_id: current_user.id)
    redirect_to project_proposals_url, notice: "Project Proposal Approved"
  end

  def decline
    @project_proposal = ProjectProposal.find(params[:id])
    @project_proposal.update(approved: 0, admin_id: current_user.id)
    redirect_to project_proposals_url, notice: "Project Proposal Declined"
  end

  def join_project_proposal
    @project_proposal = ProjectProposal.find(params[:project_proposal_id])
    @project_join = ProjectJoin.new(project_join_params)
    @project_join.user_id = @user.id
    if @project_join.save
      redirect_to project_proposal_path(@project_proposal.slug),
                  notice: "You joined this project."
    else
      redirect_to project_proposal_path(@project_proposal.slug),
                  alert:
                    "You already joined this project or something went wrong."
    end
  end

  def unjoin_project_proposal
    @project_proposal = ProjectProposal.find(params[:project_proposal_id])
    @project_join = ProjectJoin.find(params[:project_join_id])
    if @project_join.delete
      redirect_to project_proposal_path(@project_proposal.slug),
                  notice: "You unjoined this project."
    else
      redirect_to project_proposal_path(@project_proposal.slug),
                  alert: "Something went wrong."
    end
  end

  private

  def create_photos
    if params[:images].present?
      params[:images]
        .first(5)
        .each do |img|
          dimension = FastImage.size(img.tempfile, raise_on_failure: true)
          Photo.create(
            image: img,
            project_proposal_id: @project_proposal.id,
            width: dimension.first,
            height: dimension.last
          )
        end
    end
  end

  def create_files
    if params[:files].present?
      params[:files].each do |f|
        RepoFile.create(file: f, project_proposal_id: @project_proposal.id)
      end
    end
  end

  def update_photos
    if params[:deleteimages].present?
      @project_proposal.photos.each do |img|
        if params[:deleteimages].include?(img.image.filename.to_s)
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
          project_proposal_id: @project_proposal.id,
          width: dimension.first,
          height: dimension.last
        )
      end
    end
  end

  def update_files
    if params["deletefiles"].present?
      @project_proposal.repo_files.each do |f|
        if params["deletefiles"].include?(f.file.id.to_s)
          # checks if the file should be deleted
          f.file.purge
          f.destroy
        end
      end
    end

    if params["files"].present?
      params["files"].each do |f|
        RepoFile.create(file: f, project_proposal_id: @project_proposal.id)
      end
    end
  end

  # Use callbacks to share common setup or constraints between actions.
  def set_project_proposal
    @project_proposal = ProjectProposal.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def project_proposal_params
    params.require(:project_proposal).permit(
      :user_id,
      :admin_id,
      :approved,
      :title,
      :description,
      :youtube_link,
      :username,
      :email,
      :client,
      :client_type,
      :client_interest,
      :client_background,
      :supervisor_background,
      :equipments,
      :project_type,
      :project_cost,
      :past_experiences,
      :linked_project_proposal_id,
      area: [],
      categories: []
    )
  end

  def create_categories
    if params[:project_proposal]["categories"].present?
      params[:project_proposal]["categories"]
        .first(5)
        .each do |c|
          Category.create(name: c, project_proposal_id: @project_proposal.id)
        end
    end
  end

  def project_join_params
    params.permit(:project_proposal_id)
  end

  def show_only_project_approved
    if !@user.admin? && @project_proposal.approved != 1
      redirect_to root_path,
                  alert: "You are not allowed to access this project."
    end
  end

  # TODO: sort_order and photo_hash for everyone
  def sort_order
    case params[:sort]
    when "newest"
      %i[created_at desc]
    when "most_likes"
      %i[like desc]
    when "most_makes"
      %i[make desc]
    when "recently_updated"
      %i[updated_at desc]
    else
      %i[created_at desc]
    end
  end

  def photo_hash
    repository_ids = @repositories.map(&:id)
    photo_ids =
      Photo
        .where(repository_id: repository_ids)
        .group(:repository_id)
        .minimum(:id)
    photos = Photo.find(photo_ids.values)
    photos.inject({}) { |h, e| h.merge!(e.repository_id => e) }
  end
end
