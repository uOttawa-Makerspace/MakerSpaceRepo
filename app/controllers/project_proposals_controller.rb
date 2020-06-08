class ProjectProposalsController < ApplicationController
  before_action :set_project_proposal, only: [:show, :edit, :update, :destroy]
  before_action :current_user
  before_action :show_only_project_approved, only: [:show]

  # GET /project_proposals
  # GET /project_proposals.json
  def index
    @user = current_user
    unless @user.admin?
      @project_proposals = ProjectProposal.all
          .joins('LEFT OUTER JOIN project_joins ON (project_proposals.id = project_joins.project_proposal_id)')
          .where('project_joins.id IS NULL')
          .order(created_at: :desc)
    else
      @project_proposals = ProjectProposal.all.order(created_at: :desc)
    end
  end

  # GET /project_proposals/1
  # GET /project_proposals/1.json
  def show
    @categories = @project_proposal.categories
    @repositories = @project_proposal.repositories.paginate(:per_page=>12,:page=>params[:page]).public_repos.order([sort_order].to_h).page params[:page]
    @photos = photo_hash
  end

  # GET /project_proposals/new
  def new
    @project_proposal = ProjectProposal.new
  end

  # GET /project_proposals/1/edit
  def edit
    @categories = @project_proposal.categories
  end

  def projects_assigned
    @project_proposals = ProjectProposal.joins(:project_joins)
                             .joins('LEFT OUTER JOIN repositories ON (project_proposals.id = repositories.project_proposal_id)')
                             .where('repositories.id IS NULL')
                             .uniq.order(created_at: :desc)
  end

  def projects_completed
    @project_proposals = ProjectProposal.joins(:repositories).uniq.order(created_at: :desc)
  end

  # POST /project_proposals
  # POST /project_proposals.json
  def create
    @project_proposal = ProjectProposal.new(project_proposal_params)
    @project_proposal.user_id = @user.try(:id)

    respond_to do |format|
      if @project_proposal.save
        create_categories
        format.html { redirect_to @project_proposal, notice: 'Project proposal was successfully created.' }
        format.json { render :show, status: :created, location: @project_proposal }
        MsrMailer.send_new_project_proposals.deliver_now
      else
        format.html { render :new }
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
        create_categories
        format.html { redirect_to @project_proposal, notice: 'Project proposal was successfully updated.' }
        format.json { render :show, status: :ok, location: @project_proposal }
      else
        format.html { render :edit }
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

  def approval
    @project_proposal = ProjectProposal.find(params[:id])
    @project_proposal.update_attributes(:approved => 1, :admin_id => current_user.id)
    flash[:notice] = "Project Proposal Approved"
    redirect_to @project_proposal
  end

  def disapproval
    @project_proposal = ProjectProposal.find(params[:id])
    @project_proposal.update_attributes(:approved => 0, :admin_id => current_user.id)
    flash[:notice] = "Project Proposal Disapproved"
    redirect_to @project_proposal
  end

  def join_project_proposal
    @project_proposal = ProjectProposal.find(params[:project_proposal_id])
    @project_join = ProjectJoin.new(project_join_params)
    @project_join.user_id = @user.id
    if @project_join.save
      flash[:notice] = "You joined this project."
      redirect_to @project_proposal
    else
      flash[:alert] = "You already joined this project or something went wrong."
      redirect_to @project_proposal
    end
  end

  def unjoin_project_proposal
    @project_proposal = ProjectProposal.find(params[:project_proposal_id])
    @project_join = ProjectJoin.find(params[:project_join_id])
    if @project_join.delete
      flash[:notice] = "You unjoined this project."
      redirect_to @project_proposal
    else
      flash[:alert] = "Something went wrong."
      redirect_to @project_proposal
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_project_proposal
      @project_proposal = ProjectProposal.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def project_proposal_params
      params.require(:project_proposal).permit(:user_id, :admin_id, :approved, :title, :description,
                                               :youtube_link, :username, :email, :client, :client_type,
                                               :client_interest, :client_background, :supervisor_background, :equipments, :area => [])
    end

    def create_categories
      params['categories'].first(5).each do |c|
        Category.create(name: c, project_proposal_id: @project_proposal.id)
      end if params['categories'].present?
    end

    def project_join_params
      params.permit(:project_proposal_id)
    end

    def show_only_project_approved
      if !@user.admin? && @project_proposal.approved != 1
        flash[:alert] = "You are not allowed to access this project."
        redirect_to root_path
      end
    end

  # TODO: sort_order and photo_hash for everyone
  def sort_order
    case params[:sort]
      when 'newest' then [:created_at, :desc]
      when 'most_likes' then [:like, :desc]
      when 'most_makes' then [:make, :desc]
      when 'recently_updated' then [:updated_at, :desc]
      else [:created_at, :desc]
    end
  end

  def photo_hash
    repository_ids = @repositories.map(&:id)
    photo_ids = Photo.where(repository_id: repository_ids).group(:repository_id).minimum(:id)
    photos = Photo.find(photo_ids.values)
    photos.inject({}) { |h,e| h.merge!(e.repository_id => e) }
  end
end
