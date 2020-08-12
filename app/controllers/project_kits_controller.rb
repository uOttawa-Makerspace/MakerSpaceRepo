class ProjectKitsController < DevelopmentProgramsController
  before_action :current_user
  before_action :signed_in
  before_action :admin_staff_access, only: %i[new create destroy mark_delivered]

  def index
    @kits = current_user.project_kits.order('delivered ASC').paginate(page: params[:page], per_page: 20)
    @all_kits = ProjectKit.all.order('created_at DESC').paginate(page: params[:page], per_page: 20) if current_user.admin? || current_user.staff?
  end

  def new
    @kit = ProjectKit.new
    @proficient_projects = ProficientProject.all.where(has_project_kit: true).order(created_at: :asc).pluck(:title, :id)
  end

  def create
    @kit = ProjectKit.new(project_kits_params)
    if @kit.save
      MsrMailer.send_kit_email(@kit.user, @kit.proficient_project_id).deliver_now
      flash[:notice] = "The kit for #{@kit.user.name} has been created !"
    else
      flash[:alert] = "There was an error creating the kit"
    end
    redirect_to project_kits_path
  end

  def destroy
    if params[:id].present? and ProjectKit.find(params[:id]).present?
      ProjectKit.find(params[:id]).destroy
      flash[:notice] = "The kit has been deleted"
    else
      flash[:alert] = "There was an error, try again later"
    end
    redirect_to project_kits_path
  end

  def populate_kit_users
    json_data = User.where('LOWER(name) like LOWER(?)', "%#{params[:search]}%").map(&:as_json)
    render json: { users: json_data }
  end

  def mark_delivered
    if params[:project_kit_id].present? and ProjectKit.find(params[:project_kit_id]).present?
      ProjectKit.find(params[:project_kit_id]).update(delivered: true)
      flash[:notice] = "The kit has been marked as delivered"
    else
      flash[:alert] = "There was an error, try again later"
    end
    redirect_to project_kits_path
  end

  private

    def project_kits_params
      params.require(:project_kit).permit(:user_id, :proficient_project_id)
    end

    def admin_staff_access
      unless current_user.admin? || current_user.staff?
        redirect_to root_path
        flash[:alert] = 'You cannot access this area.'
      end
    end
end
