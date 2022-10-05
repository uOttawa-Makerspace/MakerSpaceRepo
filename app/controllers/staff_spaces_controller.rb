class StaffSpacesController < StaffAreaController
  def change_space_list
    if params[:user_id].present? && User.find(params[:user_id]).present? &&
         User.find(params[:user_id]).staff?
      repo_user = User.find(params[:user_id])
      space_list = params[:space].present? ? params[:space] : []

      space_list.each do |space|
        StaffSpace.find_or_create_by(space_id: space, user: repo_user)
      end

      repo_user.staff_spaces.where.not(space_id: space_list).destroy_all

      flash[:notice] = "Successfully changed spaces for the user."
      redirect_to user_path(repo_user.username)
    else
      flash[
        :alert
      ] = "Make sure you selected spaces and a user and that the user is at least staff."
      redirect_back(fallback_location: root_path)
    end
  end
  def bulk_add_users
    if params[:space_ids].present? && params[:user_ids].present?
      space_list = params[:space_ids]
      user_list = params[:user_ids]

      space_list.each do |space|
        user_list.each do |user_name|
          if User.find_by(username: user_name).present?
            user = User.find_by(username: user_name)
            if !user.staff? || !user.admin?
              user.role = "staff"
              user.save
            end
            StaffSpace.find_or_create_by(space_id: space, user_id: user.id)
          end
        end
      end

      flash[:notice] = "Successfully added users to spaces."
      redirect_back(fallback_location: root_path)
    else
      flash[:alert] = "Make sure you selected spaces and users."
      redirect_back(fallback_location: root_path)
    end
  end
end
