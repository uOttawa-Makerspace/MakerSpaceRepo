class StaffSpacesController < StaffAreaController
  def bulk_add_users
    if params[:space_ids].present? && params[:user_ids].present?
      space_list = params[:space_ids]
      user_list = params[:user_ids]

      space_list.each do |space|
        user_list.each do |user_name|
          user = User.find_by(username: user_name)
          next unless user
          if !user.staff? || !user.admin?
            user.role = "staff"
            user.save
          end
          StaffSpace.find_or_create_by(space_id: space, user_id: user.id)
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
