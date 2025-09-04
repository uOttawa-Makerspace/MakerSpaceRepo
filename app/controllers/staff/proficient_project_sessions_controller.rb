class Staff::ProficientProjectSessionsController < StaffDashboardController
  layout "staff_area"

  def show
    @current_proficient_project_session = ProficientProjectSession.find(params[:id])
    return if current_user.staff?
      redirect_to development_programs_path
      flash[:alert] = 
"Only admin members or staff members may view the session."
  end

  def proficient_project_session_params
    params.require(:proficient_project_session).permit(
      :certification_id,
      :proficient_project_id,
      :level,
      :user_id
    )
  end
end
