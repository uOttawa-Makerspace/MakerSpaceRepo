class ProjectKitsController < DevelopmentProgramsController
  before_action :current_user
  before_action :signed_in

  def index
    @kits = current_user.project_kits.order('delivered ASC').paginate(page: params[:page], per_page: 20)
    @all_kits = ProjectKit.all.order('created_at DESC').paginate(page: params[:page], per_page: 20) if current_user.admin?
  end

  def mark_delivered
    if current_user.admin? || current_user.staff?
      if params[:project_kit_id].present? and ProjectKit.find(params[:project_kit_id]).present?
        ProjectKit.find(params[:project_kit_id]).update(delivered: true)
        flash[:notice] = "The kit has been marked as delivered"
      else
        flash[:alert] = "There was an error, try again later"
      end
      redirect_to project_kits_path
    else
      redirect_to root_path
      flash[:alert] = 'You cannot access this area.'
    end
  end

end
