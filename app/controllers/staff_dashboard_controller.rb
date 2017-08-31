class StaffDashboardController < StaffAreaController
  before_action :default_space

  def index
  end

  def sign_out_users
    if params['dropped_users'].present?
      users = User.where(username: params['dropped_users']).map(&:id)
      lab_sessions = LabSession.where(user_id: users)
      lab_sessions.update_all(sign_out_time: Time.now)
    end
    redirect_to staff_dashboard_index_path(space_id: @space.id)
  end

  def sign_in_users
    if params['added_users'].present?
      users = User.where(username: params['added_users'])
      users.each do |user|
        lab_session = LabSession.new(user_id: user.id, pi_reader_id: PiReader.find_by(space_id: @space.id).id, sign_in_time: Time.now, sign_out_time: Time.now+3.hours)
        unless lab_session.save
          flash[:alert] = "Error signing #{user.name} in"
        end
      end
    end
    redirect_to staff_dashboard_index_path(space_id: @space.id)
  end

  def change_space

    if new_space = Space.find_by(name: params['space_name'])
      if current_sesh = current_user.lab_sessions.where('sign_out_time > ?', Time.now).last
        current_sesh.sign_out_time = Time.now
        current_sesh.save
      end
      if (reader =  PiReader.find_by(space_id: new_space.id))
        new_sesh = LabSession.new(
                      user_id: current_user.id,
                      sign_in_time: Time.now,
                      sign_out_time: Date.tomorrow,
                      space_id: reader.space.id,
                      mac_address: reader.pi_mac_address)
        if new_sesh.save
          flash[:notice] = "Space changed successfully"
        else
          flash[:alert] = "Something went wrong"
        end
      end
    end
    redirect_to :back
  end

  def search
    unless params[:query].blank?
      @query = params[:query]
      @users = User.where('LOWER(name) like LOWER(?) OR
                           LOWER(email) like LOWER(?) OR
                           LOWER(username) like LOWER(?)',
                           "%#{@query}%", "%#{@query}%", "%#{@query}%")
                           .includes(:lab_sessions)
                           .order(:updated_at)
    else
      redirect_to (:back)
      flash[:alert] = "Invalid parameters!"
    end
  end

  private

  def default_space
    @space = current_user.lab_sessions.last.space rescue Space.all.first
  end

end
