# frozen_string_literal: true

class StaffDashboardController < StaffAreaController
  # NOTE: @space is set by StaffAreaController
  
  def index
    # Strict loading because this is used in table views
    # FIXME: Temporarily disabled because of space 119
    @signed_in_users = User
                         .includes(certifications: {training_session: [:training, :user]})
                         .includes(:lab_sessions)
                         .where(lab_sessions: {sign_out_time: Time.zone.now.., space: @space })

    @signed_out_users = @space.recently_signed_out_users
    
    respond_to do |format|
      format.html do
        @users = User.order(id: :desc).limit(10)
        @certifications_on_space =
          proc do |user, space_id|
            user
              .certifications
              .joins(:training, training: :spaces)
              .where(trainings: { spaces: { id: space_id } })
          end
        @all_user_certs = proc { |user| user.certifications }
        @printers_in_use =
          PrinterSession.order(created_at: :desc).where(in_use: true)
        @table_column_count = 0
      end
      format.json do
        render json: {
                 space: @space.as_json,
                 space_users:
                   @space
                     .signed_in_users
                     .map { |u| u.attributes.except "password" }
                     .as_json,
                 space_list: Space.all.pluck(:name, :id)
               }
      end
    end
  end

  def refresh_capacity
    respond_to do |format|
      format.html { render partial: "capacity_alert", layout: false }
    end
  end

  def refresh_tables
    return head :not_modified if params[:token] == @space.signed_in_users.pluck(:id).join("")
    @users = User.order(id: :desc).limit(10)
    @certifications_on_space =
      proc do |user, space_id|
        user
          .certifications
          .joins(:training, training: :spaces)
          .where(trainings: { spaces: { id: space_id } })
      end
    @printers_in_use =
      PrinterSession.order(created_at: :desc).where(in_use: true)
    @all_user_certs = proc { |user| user.certifications }
    @all_user_memberships = Membership.where(user_id: @space.signed_in_users.pluck(:id)).active.pluck(:user_id)
    @all_sign_out_memberships = Membership.where(user_id: @space.recently_signed_out_users.pluck(:id)).active.pluck(:user_id)
    recent_membership = @space.signed_in_users.first.memberships.active.order(end_date: :desc).first
    recent_expiration_date = ""
    recent_expiration_date = recent_membership.end_date.to_date unless recent_membership.nil?
    render json: {
            users: @space.signed_in_users.pluck(:name, :email, :username),
            certification: Certification.select('certifications.id, certifications.user_id, trainings.name_en')
            .joins(:training).where(user_id: @space.signed_in_users.pick(:id)).group_by(&:user_id).to_a,
            has_membership: @space.signed_in_users.first.has_active_membership?,
            expiration_date: recent_expiration_date,
            is_student: @space.signed_in_users.first.student?,
            signed_sheet: @space.signed_in_users.first.walk_in_safety_sheets.any?,
             signed_out:
               render_to_string(
                 partial: "staff_dashboard/signed_out_table",
                 locals: {
                   space: @space,
                   all_user_certs: @all_user_certs,
                   certifications_on_space: @certifications_on_space,
                   all_user_memberships: @all_sign_out_memberships
                 },
                 formats: [:html]
               ),
             signed_in:
               render_to_string(
                 partial: "staff_dashboard/signed_in_table",
                 locals: {
                   space: @space,
                   all_user_certs: @all_user_certs,
                   certifications_on_space: @certifications_on_space,
                   all_user_memberships: @all_user_memberships
                 },
                 formats: [:html]
               )
           }
  end

  def import_excel
    begin
      file = params[:file]
      file_ext = File.extname(file.original_filename)
      faulty_users = 0
      faulty_user_data = []
      raise "Unknown file type: #{file.original_filename}" unless %w[.xls .xlsx].include?(file_ext)
      spreadsheet =
        (
          if file_ext == ".xls"
            Roo::Excel.new(file.path)
          else
            Roo::Excelx.new(file.path)
          end
        )
      (1..spreadsheet.last_row).each do |i|
        next if spreadsheet.row(i)[0].blank?
        user_data = spreadsheet.row(i)[0].downcase
        user =
          User.where(
            "lower(email) = ? OR lower(name) = ? OR lower(username) = ?",
            user_data,
            user_data,
            user_data
          )
        faulty_users += 1 and faulty_user_data << user_data and
          next if user.blank?
        LabSession.create(
          user: user.last,
          space_id: @space.id,
          sign_in_time: Time.zone.now,
          sign_out_time: Time.zone.now + 8.hours
        )
      end
      flash[
        :notice
      ] = "The file has been processed and users have been signed in ! "
      if faulty_users > 0
        flash[
          :alert_yellow
        ] = "Please note that #{faulty_users} user(s) did not get signed in because they were not found in the system."
        flash[:alert] = "Users with error: #{faulty_user_data.join(", ")}"
      end
    rescue StandardError => e
      flash[
        :alert
      ] = "An error occured while uploading the log in file, please try again later: #{e}"
    end
    redirect_to staff_dashboard_index_path
  end

  def sign_out_users
    if params[:dropped_users].present?
      @users = User.order(id: :desc).limit(10)
      @certifications_on_space =
        proc do |user, space_id|
          user
            .certifications
            .joins(:training, training: :spaces)
            .where(trainings: { spaces: { id: space_id } })
        end
      @all_user_certs = proc { |user| user.certifications }
      # Search user by username
      User
        .where(username: params[:dropped_users])
        .each do |user|
          # get only the latest session, if they're not signed out yet
          LabSession.active_for_user(user).last.sign_out
        end
    end
    respond_to do |format|
      format.html { redirect_to staff_dashboard_index_path }
      format.js
      format.json { render json: { status: "ok" } }
    end
  end

  def add_signed_in_users_to_teams
    if @space.jmts?
      @space.signed_in_users.each do |user|
        user.programs.find_or_create_by(program_type: Program::TEAMS)
      end

      flash[:notice] = "Successfully added all users to teams program"
    else
      flash[:alert] = "You can't perform this operation in this space."
    end

    redirect_to staff_dashboard_index_path
  end

  def sign_out_all_users
    space = @space
    @certifications_on_space =
      proc do |user, space_id|
        user
          .certifications
          .joins(:training, training: :spaces)
          .where(trainings: { spaces: { id: space_id } })
      end
    @all_user_certs = proc { |user| user.certifications }
    @users = User.order(id: :desc).limit(10)

    space.signed_in_users.each do |user|
      # Lab sessions where sign out did not happen yet (greater than time now)
      LabSession.active_for_user(user).last.sign_out
    end
    respond_to do |format|
      format.html do
        redirect_to staff_dashboard_index_path(space_id: @space.id)
      end
      format.json { render json: { status: "ok" } }
    end
  end

  def sign_in_users
    alert = []

    # Staff dashboard changed, but we keep compat with app.
    user_query = params[:added_users] || params[:username]

    users = User.where(username: user_query).find_each do |user|
      lab_session =
        LabSession.new(
          user_id: user.id,
          space_id: @space.id,
          sign_in_time: Time.zone.now,
          sign_out_time: Time.zone.now + 6.hours
        )
      alert << user.name unless lab_session.save
    end

    respond_to do |format|
      format.html do
        flash[:alert] = "Error signing #{alert.join(', ')} in" if alert.length > 0
        redirect_to staff_dashboard_index_path(space_id: @space.id)
      end
      format.js
      format.json { render json: { status: 'ok' } }
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
    if status
  flash[:notice] = "Space changed successfully"
else
  flash[:alert] = "Something went wrong"
end
    respond_to do |format|
      format.html do
        redirect_back(fallback_location: staff_dashboard_index_path)
      end
      format.json { render json: { status: status ? "ok" : "error" } }
    end
  end

  def link_rfid
    status = true

    if params[:user_id].present? && params[:card_number].present?
      rfid = Rfid.find_by(card_number: params[:card_number])
      rfid.user_id = params[:user_id]
      status = false unless rfid.save
    end

    respond_to do |format|
      format.html do
        if status
  flash[:notice] = "RFID linked successfully"
else
  flash[
            :alert
          ] = "Something went wrong while linking the RFID, please try again later."
end
        redirect_back(fallback_location: root_path)
      end
      format.json { render json: { status: status ? "ok" : "error" } }
    end
  end

  def unlink_rfid
    status = true

    if params[:card_number].present?
      rfid = Rfid.find_by(card_number: params[:card_number])
      rfid.user_id = nil
      if @user.location != "no sign in yet" &&
           pi = Space.find_by(name: @user.location)&.pi_readers&.first
        new_mac = pi.pi_mac_address
        rfid.mac_address = new_mac
      end
      status = false unless rfid.save
    end

    respond_to do |format|
      format.html do
        if status
  flash[:notice] = "RFID unlinked successfully"
else
  flash[
            :alert
          ] = "Something went wrong while unlinking the RFID, please try again later."
end
        redirect_back(fallback_location: root_path)
      end
      format.json { render json: { status: status ? "ok" : "error" } }
    end
  end

  def user_profile
    if params[:username].present? and
         User.find_by_username(params[:username]).present?
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
        format.html do
          redirect_to staff_dashboard_index_path, alert: "No search parameters."
        end
        format.json { render json: { error: "no params" } }
      elsif params[:username].present?
        @users = User.where("username = ?", params[:username])
      else
        @query = params[:query]
        @users =
          User
            .where(
              "LOWER(UNACCENT(name)) like LOWER(UNACCENT(?)) OR
                           LOWER(UNACCENT(email)) like LOWER(UNACCENT(?)) OR
                           LOWER(UNACCENT(username)) like LOWER(UNACCENT(?))",
              "%#{@query}%",
              "%#{@query}%",
              "%#{@query}%"
            )
            .includes(lab_sessions: :space)
            .order(:updated_at)
      end
      format.html
      format.json { render json: @users.as_json }
    end
  end

  def open_modal
    @sign_in_modal = User.find(params[:id])
    respond_to { |format| format.js }
  end

  def present_users_report
    respond_to do |format|
      format.html
      format.xlsx do
        send_data ReportGenerator
                    .generate_space_present_users_report(@space.id)
                    .to_stream
                    .read,
                  filename:
                    "#{@space.name}_#{Time.new.strftime("%Y-%m-%d_%Hh%M")}_present_users_report.xlsx"
      end
    end
  end

  def populate_users
    json_data = User.fuzzy_search(params[:search]).as_json(only: %i[name username])
    render json: { users: json_data }
  end

  private

  def update_lab_session
    current_sesh =
      current_user.lab_sessions.where("sign_out_time > ?", Time.zone.now).last
    return unless current_sesh.present?
      current_sesh.sign_out_time = Time.zone.now
      current_sesh.save
    
  end
end
