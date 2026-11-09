class ProjectKitsController < DevelopmentProgramsController
  before_action :current_user
  before_action :signed_in
  before_action :with_development_header
  before_action :staff_admin_access, only: %i[new create destroy mark_delivered populate_kit_users]

  def index
    @pagy, @kits = pagy(current_user.project_kits.order("delivered ASC"), limit: 20)

    if current_user.admin?
      @pagy_all, @all_kits = pagy(ProjectKit.order("delivered ASC"), page_key: "page_all", limit: 20)
    end
  end

  def new
    @kit = ProjectKit.new
    @proficient_projects =
      ProficientProject
        .all
        .where(has_project_kit: true)
        .order(created_at: :asc)
        .pluck(:title, :id)
  end

  def create
    @kit = ProjectKit.new(project_kits_params)
    if @kit.save
      MsrMailer.send_kit_email(
        @kit.user,
        @kit.proficient_project_id
      ).deliver_now
      flash[:notice] = "The kit for #{@kit.user.name} has been created !"
    else
      flash[:alert] = validation_message(@kit, "errors.project_kits.not_created")
    end
    redirect_to project_kits_path
  end

  def destroy
    kit = ProjectKit.find(params[:id])
    write_flash(kit, "errors.project_kits.not_deleted", "The kit has been deleted") { kit.destroy }
    redirect_to project_kits_path
  end

  def populate_kit_users
    json_data =
      User.directory_search(params[:search]).select(:id, :name, :username)
    render json: { users: json_data }
  end

  def mark_delivered
    kit = ProjectKit.find_by(id: params[:project_kit_id])

    if kit
      kit.update(delivered: true)
      flash[:notice] = "The kit has been marked as delivered."
    else
      flash[:alert] = "Project kit ID was not found."
    end

    redirect_to project_kits_path
  end

  private

  def project_kits_params
    params.require(:project_kit).permit(:user_id, :proficient_project_id)
  end

  def staff_admin_access
    unless current_user.admin? || current_user.staff?
      redirect_to project_kits_path
      flash[:alert] = "You cannot access this area."
    end
  end
end
