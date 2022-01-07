class StaffSpacesController < StaffAreaController

  def change_space_list
    if params[:user_id].present? && User.find(params[:user_id]).present? && User.find(params[:user_id]).staff?

      repo_user = User.find(params[:user_id])
      space_list = params[:space].present? ? params[:space] : []

      space_list.each do |space|
        StaffSpace.find_or_create_by(space_id: space, user: repo_user)
      end

      repo_user.staff_spaces.where.not(space_id: space_list).destroy_all

      flash[:notice] = "Successfully changed spaces for the user."
      redirect_to user_path(repo_user.username)
    else
      flash[:alert] = "Make sure you selected spaces and a user and that the user is at least staff."
      redirect_back(fallback_location: root_path)
    end
  end

end
