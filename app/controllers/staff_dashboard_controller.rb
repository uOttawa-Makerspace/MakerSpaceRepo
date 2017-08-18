class StaffDashboardController < StaffAreaController
  before_action :default_space

  def index
  end

  def sign_out_users
    if params['dropped_users'].present?
      params['dropped_users'].each do |username|
        user = User.find_by(username: username)
        lab_session = @space.lab_sessions.where(user_id: user.id).last
        lab_session.sign_out_time = Time.now #sign user out of user.lab_sessions.last.space
        unless lab_session.save
          flash[:alert] = "Error signing #{username} out"
        end
      end
    end
    redirect_to :back
  end

  def sign_in_users
    if params['added_users'].present?
      params['added_users'].each do |username|
        user = User.find_by(username: username)
        lab_session = LabSession.new(user_id: user.id, sign_in_time: Time.now, sign_out_time: Date.tomorrow, mac_address: @space.pi_readers.first.pi_mac_address, pi_reader_id: @space.pi_readers.first.id)
        unless lab_session.save
          flash[:alert] = "Error signing #{username} in"
        end
      end
    end
    redirect_to :back
  end

  def change_space

    if new_space = Space.find_by(name: params['space_name'])
      current_sesh = current_user.lab_sessions.last
      current_sesh.sign_out_time = Time.now
      current_sesh.save
      new_sesh = LabSession.new(
                    user_id: current_user.id,
                    sign_in_time: Time.now,
                    sign_out_time: Date.tomorrow,
                    pi_reader_id: new_space.pi_readers.first.id,
                    mac_address: new_space.pi_readers.first.pi_mac_address)
      if new_sesh.save
        flash[:notice] = "Space changed successfully"
      else
        flash[:alert] = "Space changed successfully"
      end
    end
    redirect_to staff_dashboard_index_path
  end

  private

  def default_space
    @space = current_user.lab_sessions.last.space
  end

end
