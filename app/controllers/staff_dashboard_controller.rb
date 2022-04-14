# frozen_string_literal: true

class StaffDashboardController < StaffAreaController

  def index
    respond_to do |format|
      format.html {
        @users = User.order(id: :desc).limit(10)
        @certifications_on_space = Proc.new { |user, space_id| user.certifications.joins(:training, training: :spaces).where(trainings: {spaces: {id: space_id} }) }
        @all_user_certs = Proc.new { |user| user.certifications }
      }
      format.json {
        render json: {space: @space.as_json, space_users: @space.signed_in_users.as_json, space_list: Space.all.pluck(:name, :id)}
      }
    end
  end

  def refresh_capacity
    respond_to do |format|
      format.js
    end
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
    respond_to do |format|
      format.html
      format.js
      format.json { render json: { "status": "ok" } }
    end
  end

  def sign_out_all_users
    space = @space
    space.signed_in_users.each do |user|
      lab_session = LabSession.where(user_id: user.id)
      lab_session.update_all(sign_out_time: Time.zone.now)
    end
    respond_to do |format|
      format.html { redirect_to staff_dashboard_index_path(space_id: @space.id) }
      format.json { render json: { "status": "ok" } }
    end
  end

  def sign_in_users
    alert = []
    if params[:added_users].present?
      users = User.where(username: params[:added_users])
      users.each do |user|
        lab_session = LabSession.new(
          user_id: user.id,
          space_id: @space.id,
          sign_in_time: Time.zone.now,
          sign_out_time: Time.zone.now + 8.hours
        )
        alert << user.name unless lab_session.save
      end
    end
    respond_to do |format|
      format.html {
        flash[:alert] = "Error signing #{alert.join(', ')} in" unless alert.length > 0
        redirect_to staff_dashboard_index_path(space_id: @space.id)
      }
      format.js
      format.json { render json: {"status": "ok"} }
    end
  end

  def change_space
    new_space = Space.find_by(id: params[:space_id])
    current_user.update(space_id: new_space.id)
    status = true
    if new_space.present? && (current_user.space_id = params[:space_id])
      @space = new_space
    else
      status = false
    end
    respond_to do |format|
      format.html {
        status ? flash[:notice] = 'Space changed successfully' : flash[:alert] = 'Something went wrong'

        if params[:training].present? and params[:training] == 'true'
          redirect_to new_staff_training_session_path
        elsif params[:questions].present? and params[:questions] == 'true'
          redirect_to questions_path
        else
          redirect_to staff_dashboard_index_path
        end
      }
      format.json { render json: { "status": "ok" } }
    end
  end

  def link_rfid
    status = true

    if params[:user_id].present? && params[:card_number].present?
      rfid = Rfid.find_by(card_number: params[:card_number])
      rfid.user_id = params[:user_id]
      unless rfid.save
        status = false
      end
    end

    respond_to do |format|
      format.html {
        status ? flash[:notice] = 'RFID linked successfully' : flash[:alert] = 'Something went wrong while linking the RFID, please try again later.'
        redirect_back(fallback_location: root_path)
      }
      format.json { render json: { "status": status ? "ok" : "error" } }
    end
  end

  def unlink_rfid
    status = true

    if params[:card_number].present?
      rfid = Rfid.find_by(card_number: params[:card_number])
      rfid.user_id = nil
      if pi = Space.find_by(name: @user.location)&.pi_readers.first
        new_mac = pi.pi_mac_address
        rfid.mac_address = new_mac
      end
      unless rfid.save
        status = false
      end
    end

    respond_to do |format|
      format.html {
        status ? flash[:notice] = 'RFID unlinked successfully' : flash[:alert] = 'Something went wrong while unlinking the RFID, please try again later.'
        redirect_back(fallback_location: root_path)
      }
      format.json { render json: { "status": status ? "ok" : "error" } }
    end  end

  def user_profile
    if params[:username].present? and User.find_by(username: params[:username]).present?
      redirect_to user_path(params[:username])
    elsif params[:query].present?
      redirect_to staff_dashboard_search_path(query: params[:query])
    else
      flash[:alert] = "A valid user must be selected"
      redirect_to staff_dashboard_index_path
    end
  end

  def search
    respond_to do |format|
      if params[:query].blank? and params[:username].blank?
        format.html {redirect_to staff_dashboard_index_path, alert: 'No search parameters.'}
        format.json {render json: {"error": "no params"}}
      elsif params[:username].present?
        @users = User.where("username = ?", params[:username])
      else
        @query = params[:query]
        @users = User.where('LOWER(UNACCENT(name)) like LOWER(UNACCENT(?)) OR
                           LOWER(UNACCENT(email)) like LOWER(UNACCENT(?)) OR
                           LOWER(UNACCENT(username)) like LOWER(UNACCENT(?))',
                            "%#{@query}%", "%#{@query}%", "%#{@query}%")
                     .includes(:lab_sessions)
                     .order(:updated_at)
      end
      format.html
      format.json { render json: @users.as_json }
    end
  end

  def present_users_report
    respond_to do |format|
      format.html
      format.xlsx { send_data ReportGenerator.generate_space_present_users_report(@space.id).to_stream.read, filename: "#{@space.name}_#{Time.new.strftime("%Y-%m-%d_%Hh%M")}_present_users_report.xlsx" }
    end
  end

  def populate_users
    json_data = User.where('LOWER(UNACCENT(name)) like LOWER(UNACCENT(?)) OR LOWER(UNACCENT(username)) like LOWER(UNACCENT(?))', "%#{params[:search]}%", "%#{params[:search]}%").map(&:as_json)
    render json: { users: json_data }
  end

  private

  def update_lab_session
    current_sesh = current_user.lab_sessions.where('sign_out_time > ?', Time.zone.now).last
    if current_sesh.present?
      current_sesh.sign_out_time = Time.zone.now
      current_sesh.save
    end
  end

end
