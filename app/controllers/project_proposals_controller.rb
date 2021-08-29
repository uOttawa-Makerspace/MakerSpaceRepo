# frozen_string_literal: true

class ProjectProposalsController < ApplicationController
  before_action :set_project_proposal, only: %i[show edit update destroy]
  before_action :current_user
  before_action :show_only_project_approved, only: [:show]

  # GET /project_proposals
  # GET /project_proposals.json
  def index
    @pending_project_proposals = ProjectProposal.all.joins(:user).filter_by_attribute(params[:search]).order(created_at: :desc).where(approved: nil).paginate(per_page: 15, page: params[:page_pending])
    @approved_project_proposals = ProjectProposal.all.joins(:user).filter_by_attribute(params[:search]).order(created_at: :desc).where(approved: 1).paginate(per_page: 15, page: params[:page_approved])
    @not_approved_project_proposals = ProjectProposal.all.joins(:user).filter_by_attribute(params[:search]).order(created_at: :desc).where(approved: 0).paginate(per_page: 15, page: params[:page_not_approved])

    respond_to do |format|
      format.js
      format.html
    end
  end

  def user_projects
    @project_proposals_joined = ProjectProposal.all.joins(:project_joins).where(project_joins: {user: current_user}).order(created_at: :desc).paginate(per_page: 15, page: params[:page])
    @user_pending_project_proposals = current_user.project_proposals.where(approved: nil).order(created_at: :desc).paginate(per_page: 15, page: params[:page])
    @approved_project_proposals = current_user.project_proposals.order(created_at: :desc).where(approved: 1).paginate(per_page: 15, page: params[:page_approved])
  end

  # GET /project_proposals/1
  # GET /project_proposals/1.json
  def show
    @categories = @project_proposal.categories
    @repositories = @project_proposal.repositories.order([sort_order].to_h).page params[:page]
    @photos = photo_hash
    @project_photos = @project_proposal.photos.joins(:image_attachment)&.first(5) || []
    @project_files = @project_proposal.repo_files.joins(:file_attachment)
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
    @assigned_project_proposals = ProjectProposal.joins(:project_joins)
                                      .joins('LEFT OUTER JOIN repositories ON (project_proposals.id = repositories.project_proposal_id)')
                                      .where('repositories.id IS NULL')
                                      .where(approved: 1)
                                      .distinct.order(created_at: :desc)
                                      .paginate(per_page: 15, page: params[:page])
  end

  def projects_completed
    @completed_project_proposals = ProjectProposal.where(approved: 1).joins(:repositories).distinct.order(created_at: :desc).paginate(per_page: 15, page: params[:page])
  end

  # POST /project_proposals
  # POST /project_proposals.json
  def create
    @project_proposal = ProjectProposal.new(project_proposal_params)
    @project_proposal.user_id = @user.try(:id)

    respond_to do |format|
      if verify_recaptcha(model: @project_proposal) && @project_proposal.save
        create_photos
        create_files
        create_categories
        format.html { redirect_to project_proposal_url(@project_proposal.slug), notice: 'Project proposal was successfully created.' }
        format.json { render json: {redirect_uri: project_proposal_url(@project_proposal.slug).to_s} }
        MsrMailer.send_new_project_proposals.deliver_now
      else
        flash[:alert] = 'An error occurred while creating the project proposal, try again later.'
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @project_proposal.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /project_proposals/1
  # PATCH/PUT /project_proposals/1.json
  def update
    @project_proposal.categories.destroy_all
    respond_to do |format|
      if @project_proposal.update(project_proposal_params)
        update_photos
        update_files
        create_categories
        format.html { redirect_to project_proposal_url(@project_proposal.slug), notice: 'Project proposal was successfully updated.' }
        format.json { render json: {redirect_uri: project_proposal_url(@project_proposal.slug).to_s} }
      else
        flash[:alert] = 'An error occurred while updating the project proposal, try again later.'
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @project_proposal.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /project_proposals/1
  # DELETE /project_proposals/1.json
  def destroy
    @project_proposal.destroy
    respond_to do |format|
      format.html { redirect_to project_proposals_url, notice: 'Project proposal was successfully deleted.' }
      format.json { head :no_content }
    end
  end

  def approve
    @project_proposal = ProjectProposal.find(params[:id])
    @project_proposal.update(approved: 1, admin_id: current_user.id)
    flash[:notice] = 'Project Proposal Approved'
    redirect_to project_proposals_url
  end

  def decline
    @project_proposal = ProjectProposal.find(params[:id])
    @project_proposal.update(approved: 0, admin_id: current_user.id)
    flash[:notice] = 'Project Proposal Declined'
    redirect_to project_proposals_url
  end

  def join_project_proposal
    @project_proposal = ProjectProposal.find(params[:project_proposal_id])
    @project_join = ProjectJoin.new(project_join_params)
    @project_join.user_id = @user.id
    if @project_join.save
      flash[:notice] = 'You joined this project.'
      redirect_to project_proposal_url(@project_proposal.slug)
    else
      flash[:alert] = 'You already joined this project or something went wrong.'
      redirect_to project_proposal_url(@project_proposal.slug)
    end
  end

  def unjoin_project_proposal
    @project_proposal = ProjectProposal.find(params[:project_proposal_id])
    @project_join = ProjectJoin.find(params[:project_join_id])
    if @project_join.delete
      flash[:notice] = 'You unjoined this project.'
      redirect_to project_proposal_url(@project_proposal.slug)
    else
      flash[:alert] = 'Something went wrong.'
      redirect_to project_proposal_url(@project_proposal.slug)
    end
  end

  private

  def create_photos
    if params[:images].present?
      params[:images].first(5).each do |img|
        dimension = FastImage.size(img.tempfile)
        Photo.create(image: img, project_proposal_id: @project_proposal.id, width: dimension.first, height: dimension.last)
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
        if params[:deleteimages].include?(img.image.filename.to_s) # checks if the file should be deleted
          img.image.purge
          img.destroy
        end
      end
    end

    if params['images'].present?
      params['images'].each do |img|
        dimension = FastImage.size(img.tempfile)
        Photo.create(image: img, project_proposal_id: @project_proposal.id, width: dimension.first, height: dimension.last)
      end
    end
  end

  def update_files
    if params['deletefiles'].present?
      @project_proposal.repo_files.each do |f|
        if params['deletefiles'].include?(f.file.id.to_s) # checks if the file should be deleted
          f.file.purge
          f.destroy
        end
      end
    end

    if params['files'].present?

      params['files'].each do |f|
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
    params.require(:project_proposal).permit(:user_id, :admin_id, :approved, :title, :description,
                                             :youtube_link, :username, :email, :client, :client_type,
                                             :client_interest, :client_background, :supervisor_background, :equipments,
                                             :project_type, :project_cost, :past_experiences, area: [])
  end

  def create_categories
    if params['categories'].present?
      params['categories'].first(5).each do |c|
        Category.create(name: c, project_proposal_id: @project_proposal.id)
      end
    end
  end

  def project_join_params
    params.permit(:project_proposal_id)
  end

  def show_only_project_approved
    if !@user.admin? && @project_proposal.approved != 1
      flash[:alert] = 'You are not allowed to access this project.'
      redirect_to root_path
    end
  end

  # TODO: sort_order and photo_hash for everyone
  def sort_order
    case params[:sort]
    when 'newest' then
      %i[created_at desc]
    when 'most_likes' then
      %i[like desc]
    when 'most_makes' then
      %i[make desc]
    when 'recently_updated' then
      %i[updated_at desc]
    else
      %i[created_at desc]
    end
  end

  def photo_hash
    repository_ids = @repositories.map(&:id)
    photo_ids = Photo.where(repository_id: repository_ids).group(:repository_id).minimum(:id)
    photos = Photo.find(photo_ids.values)
    photos.inject({}) { |h, e| h.merge!(e.repository_id => e) }
  end
end
