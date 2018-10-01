class StaffDashboardController < StaffAreaController

  def index
    @printers = Printer.all
  end

  def sign_out_users
    if params['dropped_users'].present?
      users = User.where(username: params['dropped_users']).map(&:id)
      lab_sessions = LabSession.where(user_id: users)
      lab_sessions.update_all(sign_out_time: Time.zone.now)
    end
    redirect_to staff_dashboard_index_path(space_id: @space.id)
  end

  def sign_out_all_users
    space = @space
    space.signed_in_users.each do |user|
      lab_session = LabSession.where(user_id: user.id)
      lab_session.update_all(sign_out_time: Time.zone.now)
    end
    redirect_to staff_dashboard_index_path(space_id: @space.id)
  end

  def sign_in_users
    if params['added_users'].present?
      users = User.where(username: params['added_users'])
      users.each do |user|
        lab_session = LabSession.new(
                        user_id: user.id,
                        space_id: @space.id,
                        sign_in_time: Time.zone.now,
                        sign_out_time: Time.zone.now + 8.hours)
        unless lab_session.save
          flash[:alert] = "Error signing #{user.name} in"
        end
      end
    end
    redirect_to staff_dashboard_index_path(space_id: @space.id)
  end

  def change_space

    if new_space = Space.find_by(name: params['space_name'])
      if current_sesh = current_user.lab_sessions.where('sign_out_time > ?', Time.zone.now).last
        current_sesh.sign_out_time = Time.zone.now
        current_sesh.save
      end
      new_sesh = LabSession.new(
                    user_id: current_user.id,
                    sign_in_time: Time.zone.now,
                    sign_out_time: Time.zone.now + 8.hours,
                    space_id: new_space.id)
      if new_sesh.save
        flash[:notice] = "Space changed successfully"
      else
        flash[:alert] = "Something went wrong"
      end
    end
    redirect_to staff_index_url
  end

  def link_rfid
    if params['user_id'].present? && params['card_number'].present?
      rfid = Rfid.find_by(card_number: params['card_number'])
      rfid.user_id = params['user_id']
      rfid.save
    end
    redirect_to :back
  end

  def unlink_rfid
    if params['card_number'].present?
      rfid = Rfid.find_by(card_number: params['card_number'])
      rfid.user_id = nil
      if pi = Space.find_by(name: @user.location)&.pi_readers.first
        new_mac = pi.pi_mac_address
        rfid.mac_address = new_mac
      end
      rfid.save
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


  def present_users_report
    respond_to do |format|
      format.html
      format.csv {send_data ReportGenerator.present_users_report(@space.id, @user.id)}
    end
  end

  def link_printer_to_user


  end

 end
