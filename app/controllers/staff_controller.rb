class StaffController < StaffAreaController

  def index
    if sort_params
      if params[:p] == "signed_in_users"
        if !params[:sort].present? && !params[:direction].present?
          params[:sort] = "lab_sessions.sign_in_time"
          params[:direction] = "desc"
        end
        @users_temp = LabSession.joins(:user).where("sign_out_time > ?", Time.now)
        if params[:location].present?
          @users_temp = @users_temp.joins("INNER JOIN pi_readers ON pi_mac_address = mac_address AND LOWER(pi_location) = LOWER('#{params[:location]}')")
        end
        @users_temp = @users_temp.order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page], :per_page => 20)
        @users = @users_temp.includes(:user).map{|session| session.user}
        @total_pages = @users_temp.total_pages
      elsif params[:p] == "new_users" || !params[:p].present?
        if !params[:sort].present? && !params[:direction].present?
          params[:sort] = "users.created_at"
          params[:direction] = "desc"
        end
        @users = User.includes(:lab_sessions).order("#{params[:sort]} #{params[:direction]}").paginate(:page => params[:page], :per_page => 20)
        @total_pages = @users.total_pages
      end
    else
      redirect_to staff_index_path
      flash[:alert] = "Invalid parameters!"
    end
  end

  def sort_params
    if (((["username","name","lab_sessions.sign_in_time","users.created_at"].include? params[:sort]) && (["desc","asc"].include? params[:direction])) || (!params[:sort].present? && !params[:direction].present?))
      return true
    end
  end

end
