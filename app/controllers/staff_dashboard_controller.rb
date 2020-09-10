# frozen_string_literal: true

class StaffDashboardController < StaffAreaController

  def index
    @users = User.order(id: :desc).limit(10)
  end

  def import_excel
    begin
      file = params[:file]
      file_ext = File.extname(file.original_filename)
      faulty_users = 0
      faulty_user_data = []
      raise "Unknown file type: #{file.original_filename}" unless [".xls", ".xlsx"].include?(file_ext)
      spreadsheet = (file_ext == ".xls") ? Roo::Excel.new(file.path) : Roo::Excelx.new(file.path)
      (1..spreadsheet.last_row).each do |i|
        next if spreadsheet.row(i)[0].blank?
        user_data = spreadsheet.row(i)[0].downcase
        user = User.where("lower(email) = ? OR lower(name) = ? OR lower(username) = ?", user_data, user_data, user_data)
        faulty_users += 1 and faulty_user_data << user_data and next if user.blank?
        LabSession.create(
            user: user.last,
            space_id: @space.id,
            sign_in_time: Time.zone.now,
            sign_out_time: Time.zone.now + 8.hours
        )
      end
      flash[:notice] = "The file has been processed and users have been signed in ! "
      if faulty_users > 0
        flash[:alert_yellow] = "Please note that #{faulty_users} user(s) did not get signed in because they were not found in the system."
        flash[:alert] = "Users with error: #{faulty_user_data.join(", ")}"
      end
    rescue StandardError => e
      flash[:alert] = "An error occured while uploading the log in file, please try again later: #{e}"
    end
    redirect_to staff_dashboard_index_path
  end

  def sign_out_users
    if params[:dropped_users].present?
      users = User.where(username: params[:dropped_users]).map(&:id)
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
    if params[:added_users].present?
      users = User.where(username: params[:added_users])
      users.each do |user|
        lab_session = LabSession.new(
          user_id: user.id,
          space_id: @space.id,
          sign_in_time: Time.zone.now,
          sign_out_time: Time.zone.now + 8.hours
        )
        flash[:alert] = "Error signing #{user.name} in" unless lab_session.save
      end
    end
    redirect_to staff_dashboard_index_path(space_id: @space.id)
  end

  def change_space
    if new_space = Space.find_by(name: params[:space_name])
      if current_sesh = current_user.lab_sessions.where('sign_out_time > ?', Time.zone.now).last
        current_sesh.sign_out_time = Time.zone.now
        current_sesh.save
      end
      new_sesh = LabSession.new(
        user_id: current_user.id,
        sign_in_time: Time.zone.now,
        sign_out_time: Time.zone.now + 8.hours,
        space_id: new_space.id
      )
      if new_sesh.save
        flash[:notice] = 'Space changed successfully'
      else
        flash[:alert] = 'Something went wrong'
      end
    end
    redirect_to staff_index_url
  end

  def link_rfid
    if params[:user_id].present? && params[:card_number].present?
      rfid = Rfid.find_by(card_number: params[:card_number])
      rfid.user_id = params[:user_id]
      rfid.save
    end
    redirect_back(fallback_location: root_path)
  end

  def unlink_rfid
    if params[:card_number].present?
      rfid = Rfid.find_by(card_number: params[:card_number])
      rfid.user_id = nil
      if pi = Space.find_by(name: @user.location)&.pi_readers.first
        new_mac = pi.pi_mac_address
        rfid.mac_address = new_mac
      end
      rfid.save
    end
    redirect_back(fallback_location: root_path)
  end

  def search
    if params[:query].blank? and params[:username].blank?
      redirect_back(fallback_location: root_path)
      flash[:alert] = 'Invalid parameters!'
    elsif params[:username].present?
      @users = User.where("username = ?", params[:username])
    else
      @query = params[:query]
      @users = User.where('LOWER(name) like LOWER(?) OR
                           LOWER(email) like LOWER(?) OR
                           LOWER(username) like LOWER(?)',
                          "%#{@query}%", "%#{@query}%", "%#{@query}%")
                   .includes(:lab_sessions)
                   .order(:updated_at)
    end
  end

  def present_users_report
    respond_to do |format|
      format.html
      format.xlsx { send_data ReportGenerator.generate_space_present_users_report(@space.id).to_stream.read, filename: "#{@space.name}_#{Time.new.strftime("%Y-%m-%d_%Hh%M")}_present_users_report.xlsx" }
    end
  end

  def populate_users
    json_data = User.where('LOWER(name) like LOWER(?)', "%#{params[:search]}%").map(&:as_json)
    render json: { users: json_data }
  end

 end
