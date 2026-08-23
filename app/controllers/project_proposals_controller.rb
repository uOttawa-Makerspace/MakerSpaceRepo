# frozen_string_literal: true

class ProjectProposalsController < SessionsController
  include TurnstileHelper

  before_action :set_project_proposal, only: %i[show edit update destroy]
  before_action :current_user

  # GET /project_proposals
  def index
    scope =
      ProjectProposal
        .includes(:user, :admin, :categories)
        .order(created_at: :desc)
        .search(search_params[:query])
        .where(approved: search_params[:approved])

    season, year = params[:semester]&.split('_')

    if ProjectProposal.seasons.keys.include?(season) && year.to_i.positive?
      scope = scope.where(season: season, year: year.to_i)
    end

    @pagy, @project_proposals = pagy(scope, limit: 15)

    respond_to do |format|
      format.js
      format.html
    end
  end

  def user_projects
    joined_scope =
      ProjectProposal
        .all
        .joins(:project_joins)
        .where(project_joins: { user: current_user })
        .order(created_at: :desc)

    pending_scope =
      current_user
        .project_proposals
        .where(approved: nil)
        .order(created_at: :desc)

    approved_scope =
      current_user
        .project_proposals
        .order(created_at: :desc)
        .where(approved: 1)

    @pagy_joined, @project_proposals_joined = pagy(joined_scope, page_key: 'page_joined', limit: 15)
    @pagy_pending, @user_pending_project_proposals = pagy(pending_scope, page_key: 'page_pending', limit: 15)
    @pagy_approved, @approved_project_proposals = pagy(approved_scope, page_key: 'page_approved', limit: 15)
  end

  # GET /project_proposals/1
  def show
    unless @project_proposal.approved?
      unless current_user&.admin? || (@project_proposal.user_id.present? && @project_proposal.user_id == current_user&.id)
        redirect_to project_proposals_path,
                    alert: 'You are not allowed to access this pending project proposal.'
        return
      end
    end

    @categories = @project_proposal.categories
    @pagy, @repositories =
      pagy(@project_proposal.repositories.order([sort_order].to_h), limit: 9)

    @project_photos = @project_proposal.photos.take(5)
    @project_files = @project_proposal.project_files
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
    @photos = @project_proposal.photos
    @files = @project_proposal.project_files
  end

  def projects_assigned
    scope =
      ProjectProposal
        .joins(:project_joins)
        .joins(
          'LEFT OUTER JOIN repositories ON (project_proposals.id = repositories.project_proposal_id)'
        )
        .where('repositories.id IS NULL')
        .where(approved: 1)
        .distinct
        .order(created_at: :desc)

    @pagy, @assigned_project_proposals = pagy(scope, limit: 15)
  end

  def projects_completed
    scope =
      ProjectProposal
        .where(approved: 1)
        .joins(:repositories)
        .distinct
        .order(created_at: :desc)

    @pagy, @completed_project_proposals = pagy(scope, limit: 15)
  end

  # POST /project_proposals
  def create
    @project_proposal =
      ProjectProposal.new(project_proposal_params.except(:categories))
    @project_proposal.user_id = @user.try(:id)

    respond_to do |format|
      if current_user.id.nil? && !verify_turnstile
        flash[:alert] = 'Captcha error, please try again'
        format.html { render :new, status: :unprocessable_content }
      elsif @project_proposal.save
        begin
          create_photos
        rescue FastImage::ImageFetchFailure,
               FastImage::UnknownImageType,
               FastImage::SizeNotFound => e
          Airbrake.notify(e)
          flash[:alert] = 'Something went wrong while uploading photos, try again later.'
          @project_proposal.destroy
          format.json { render json: { redirect_uri: request.path } }
          format.html { redirect_back fallback_location: request.path }
        else
          create_files
          create_categories
          @project_proposal.save
          format.html do
            redirect_to project_proposal_path(@project_proposal.slug),
                        notice: 'Project proposal was successfully created.'
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
        flash[:alert] = 'An error occurred while creating the project proposal, try again later.'
        format.html { render :new, status: :unprocessable_content }
        format.json do
          render json: @project_proposal.errors, status: :unprocessable_content
        end
      end
    end
  end

  def create_revision
    if params[:old_project_proposal_id] &&
         ProjectProposal.where(id: params[:old_project_proposal_id]).present?
      @old_project_proposal = ProjectProposal.find(params[:old_project_proposal_id])
      values = @old_project_proposal.attributes.except(
        'id',
        'user_id',
        'admin_id',
        'approved',
        'slug',
        'season',
        'year'
      )
      values['title'] = "Revision of #{@old_project_proposal.title}"
      values['linked_project_proposal_id'] = params[:old_project_proposal_id]

      @project_proposal = ProjectProposal.new(values)
      @project_proposal.user_id = current_user&.id
      @project_proposal.save!

      if @old_project_proposal.photos.attached?
        @old_project_proposal.photos.each do |photo|
          @project_proposal.photos.attach(photo.blob)
        end
      end

      if @old_project_proposal.project_files.attached?
        @old_project_proposal.project_files.each do |file|
          @project_proposal.project_files.attach(file.blob)
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
          format.html do
            redirect_to project_proposal_path(@project_proposal.slug),
                        notice:
                          'The project proposal revision has been successfully created.'
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
                          'An error occured while creating the Project proposal revision, please try again later.'
          end
        end
      end
    else
      redirect_back(
        fallback_location: root_path,
        alert:
          'An error occured while trying to create a project proposal revision, please try again later.'
      )
    end
  end

  # PATCH/PUT /project_proposals/1
  def update
    @project_proposal.categories.destroy_all
    respond_to do |format|
      if @project_proposal.update(project_proposal_params.except(:categories))
        update_photos
        update_files
        create_categories

        format.html do
          redirect_to project_proposal_path(@project_proposal.slug),
                      notice: 'Project proposal was successfully updated.'
        end
        format.json do
          render json: {
                   redirect_uri:
                   project_proposal_path(@project_proposal.slug).to_s
                 }
        end
      else
        flash[:alert] = 'An error occurred while updating the project proposal, try again later.'
        format.html { render :edit, status: :unprocessable_content }
        format.json do
          render json: @project_proposal.errors, status: :unprocessable_content
        end
      end
    end
  end

  # DELETE /project_proposals/1
  def destroy
    return unless current_user.admin?
    @project_proposal.destroy
    respond_to do |format|
      format.html do
        redirect_to project_proposals_url,
                    notice: 'Project proposal was successfully deleted.'
      end
      format.json { head :no_content }
    end
  end

  def approve
    @project_proposal = ProjectProposal.find(params[:id])
    @project_proposal.update(approved: 1, admin_id: current_user.id)
    redirect_to project_proposals_url, notice: 'Project Proposal Approved'
  end

  def decline
    @project_proposal = ProjectProposal.find(params[:id])
    @project_proposal.update(approved: 0, admin_id: current_user.id)
    redirect_to project_proposals_url, notice: 'Project Proposal Declined'
  end

  def join_project_proposal
    @project_proposal = ProjectProposal.find(params[:project_proposal_id])
    @project_join = ProjectJoin.new(project_join_params)
    @project_join.user_id = @user.id
    if @project_join.save
      redirect_to project_proposal_path(@project_proposal.slug),
                  notice: 'You joined this project.'
    else
      redirect_to project_proposal_path(@project_proposal.slug),
                  alert:
                    'You already joined this project or something went wrong.'
    end
  end

  def unjoin_project_proposal
    @project_proposal = ProjectProposal.find(params[:project_proposal_id])
    @project_join = ProjectJoin.find(params[:project_join_id])
    if @project_join.delete
      redirect_to project_proposal_path(@project_proposal.slug),
                  notice: 'You unjoined this project.'
    else
      redirect_to project_proposal_path(@project_proposal.slug),
                  alert: 'Something went wrong.'
    end
  end

  private

  def search_params
    @search_params ||= {
      query: params[:query],
      approved: params[:status]&.map { |s| s == 'nil' ? nil : s } || [0, 1, nil]
    }
  end

  def create_photos
    images = params[:images] || params.dig(:project_proposal, :images)
    return unless images.present?

    images.first(5).each do |img|
      FastImage.size(img.tempfile, raise_on_failure: true) if img.respond_to?(:tempfile)
      @project_proposal.photos.attach(img)
    end
  end

  def create_files
    files = params[:files] || params.dig(:project_proposal, :files)
    return unless files.present?

    files.each do |f|
      @project_proposal.project_files.attach(f)
    end
  end

  def update_photos
    delete_images = params[:deleteimages] || params.dig(:project_proposal, :deleteimages)
    if delete_images.present?
      @project_proposal.photos.attachments.each do |attachment|
        if delete_images.include?(attachment.filename.to_s) || delete_images.include?(attachment.id.to_s)
          attachment.purge
        end
      end
    end

    images = params[:images] || params.dig(:project_proposal, :images)
    return unless images.present?

    images.each do |img|
      FastImage.size(img.tempfile, raise_on_failure: true) if img.respond_to?(:tempfile)
      @project_proposal.photos.attach(img)
    end
  end

  def update_files
    delete_files = params[:deletefiles] || params.dig(:project_proposal, :deletefiles)
    if delete_files.present?
      @project_proposal.project_files.attachments.each do |attachment|
        if delete_files.include?(attachment.filename.to_s) || delete_files.include?(attachment.id.to_s)
          attachment.purge
        end
      end
    end

    files = params[:files] || params.dig(:project_proposal, :files)
    return unless files.present?

    files.each do |f|
      @project_proposal.project_files.attach(f)
    end
  end

  def set_project_proposal
    @project_proposal = ProjectProposal.find_by(slug: params[:id]) || ProjectProposal.find_by(id: params[:id])
    return if @project_proposal

    redirect_to project_proposals_path, alert: 'Project proposal not found'
  end

  def project_proposal_params
    permitted = [
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
      :prototype_cost,
      :past_experiences,
      :linked_project_proposal_id,
      { area: [], categories: [], photos: [], project_files: [] }
    ]

    permitted += %i[season year] if current_user&.admin?

    params.require(:project_proposal).permit(permitted)
  end

  def create_categories
    return unless params.dig(:project_proposal, 'categories').present?

    params[:project_proposal]['categories'].first(5).each do |c|
      Category.create(name: c, project_proposal_id: @project_proposal.id)
    end
  end

  def project_join_params
    params.permit(:project_proposal_id)
  end

  def sort_order
    case params[:sort]
    when 'newest'
      %i[created_at desc]
    when 'most_likes'
      %i[like desc]
    when 'most_makes'
      %i[make desc]
    when 'recently_updated'
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
