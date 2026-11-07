# frozen_string_literal: true

class StaffDashboardController < StaffAreaController
  # NOTE: @space is set by StaffAreaController
  
  def index
    # Strict loading because this is used in table views
    # FIXME: Temporarily disabled because of space 119
    @signed_in_users = User
      .where(id: LabSession.active.where(space: @space).select(:user_id))
      .includes(certifications: {training_session: [:training, :user]})
      .includes(:lab_sessions, latest_lab_session: :space)

    @signed_out_users = @space.recently_signed_out_users

    respond_to do |format|
      format.html do
        load_table_context
        @printers_in_use =
          PrinterSession.order(created_at: :desc).where(in_use: true)
        @table_column_count = 0
      end
      format.json do
        signed_in_user_ids = @space.signed_in_users.map(&:id)
        users_with_certs = User
          .where(id: signed_in_user_ids)
          .includes(certifications: { training_session: :training })

        render json: {
          space: @space.as_json,
          space_users:
            users_with_certs
              .map do |u|
                u.serializable_hash.merge({
                  "certifications" => u.certifications.map do |c|
                    {
                      id: c.id,
                      name: c.training_session&.training&.name_en || "Unknown"
                    }
                    end,
                    "signed_safety_sheet" => u.walk_in_safety_sheets.any?,
                    "membership_status" => u.has_active_membership?
                  }
                )
              end
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
    signed_in_users = @space.signed_in_users
    return head :not_modified if params[:token] == signed_in_users.map(&:id).join("")

    load_table_context
    @printers_in_use =
      PrinterSession.order(created_at: :desc).where(in_use: true)
    @all_user_memberships = Membership.where(user_id: signed_in_users.map(&:id)).active.pluck(:user_id)
    @all_sign_out_memberships = Membership.where(user_id: @space.recently_signed_out_users.pluck(:id)).active.pluck(:user_id)
    render json: latest_sign_in_details(signed_in_users).merge(
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
           )
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

  # Signs each listed user out of their latest active session. Users who are not
  # signed in, and usernames that match no user, change nothing and are reported
  # back (flash for HTML; JSON lists signed_out, not_signed_in and not_found).
  def sign_out_users
    # An array of strings, or a single string, is accepted; blanks, hashes and repeats are ignored.
    dropped = params[:dropped_users]
    dropped = [dropped] if dropped.is_a?(String)
    usernames = (dropped.is_a?(Array) ? dropped : [])
                      .select { |name| name.is_a?(String) }.map(&:strip).reject(&:blank?).uniq(&:downcase)
    users = User.where(username: usernames).to_a
    signed_out = []
    not_signed_in = []

    users.each do |user|
      # get only the latest session, if they're not signed out yet
      session = LabSession.active_for_user(user).last
      if session
        session.sign_out
        signed_out << user
      else
        not_signed_in << user
      end
    end
    # users.username is case-insensitive (citext), so compare the same way.
    found = users.map { |user| user.username.downcase }
    not_found = usernames.reject { |name| found.include?(name.downcase) }

    respond_to do |format|
      format.html do
        notes = []
        notes << "Not signed in: #{not_signed_in.map(&:name).join(', ')}" if not_signed_in.any?
        notes << "Unknown username: #{not_found.join(', ')}" if not_found.any?
        flash[:alert] = notes.join(". ") if notes.any?
        redirect_to staff_dashboard_index_path
      end
      format.js { load_table_context }
      format.json do
        render json: {
          status: "ok",
          signed_out: signed_out.map(&:username),
          not_signed_in: not_signed_in.map(&:username),
          not_found: not_found
        }
      end
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

    space.signed_in_users.each do |user|
      # Lab sessions where sign out did not happen yet (greater than time now)
      LabSession.active_for_user(user).last&.sign_out
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
      format.js { load_table_context }
      format.json { render json: { status: 'ok' } }
    end
  end

  def change_space
    new_space = Space.find_by(id: params[:space_id])
    errors = nil
    if new_space.nil?
      http_status = :not_found
      message = "Space not found"
    elsif current_user.update(space_id: new_space.id)
      @space = new_space
      flash[:notice] = "Space changed successfully"
    else
      errors = current_user.errors.full_messages
      http_status = :unprocessable_content
      message = "Space not changed: #{errors.join(', ')}"
    end
    respond_to do |format|
      format.html do
        flash[:alert] = message if http_status
        redirect_back(fallback_location: staff_dashboard_index_path)
      end
      format.json do
        if http_status
          render json: { status: "error", error: message, errors: errors }.compact, status: http_status
        else
          render json: { status: "ok" }
        end
      end
    end
  end

  # Links a card to a user through Rfid.link_to_user!, so a card no reader ever
  # saw is created and a card another user holds, or a user who already has a
  # card, is refused with the reason (flash for HTML, 422 body for JSON).
  def link_rfid
    error = nil
    http_status = :unprocessable_content

    if params[:user_id].blank? || params[:card_number].blank?
      error = "card_number and user_id are required"
    else
      card_number = params[:card_number]
      user = User.find_by(id: params[:user_id].to_s.match?(/\A\d+\z/) ? params[:user_id] : nil)
      if user.nil?
        error = "user not found"
        http_status = :not_found
      elsif !Rfid.valid_card_number?(card_number)
        error = "card number is invalid"
      else
        error = Rfid.link_to_user!(card_number, user)
      end
    end

    respond_to do |format|
      format.html do
        if error
          flash[:alert] = "RFID not linked: #{error}"
        else
          flash[:notice] = "RFID linked successfully"
        end
        redirect_back(fallback_location: root_path)
      end
      format.json do
        if error
          render json: { status: "error", error: error }, status: http_status
        else
          render json: { status: "ok" }
        end
      end
    end
  end

  # Unlinks exactly the card it is given through Rfid.unlink_card!, which
  # re-homes it to the first reader of the staff member's assigned space. A card
  # that is already unlinked changes nothing and says so.
  def unlink_rfid
    if params[:card_number].blank?
      error = "card_number is required"
      http_status = :unprocessable_content
    else
      begin
        outcome = Rfid.unlink_card!(params[:card_number].to_s, actor: current_user)
      rescue Rfid::OwnerChanging
        error = "card is changing, try again"
        http_status = :conflict
      end
      if outcome == :not_found
        error = "RFID card not found"
        http_status = :not_found
      end
    end

    respond_to do |format|
      format.html do
        if error
          flash[:alert] = error
        elsif outcome == :already_unlinked
          flash[:notice] = "RFID was already unlinked"
        else
          flash[:notice] = "RFID unlinked successfully"
        end
        redirect_back(fallback_location: root_path)
      end
      format.json do
        if error
          render json: { status: "error", error: error }, status: http_status
        elsif outcome == :already_unlinked
          render json: { status: "ok", already_unlinked: true }
        else
          render json: { status: "ok" }
        end
      end
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
            .text_search(@query)
            .includes(:lab_sessions, latest_lab_session: :space)
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

  # What the table partials (refresh_tables, the sign out JS response) read.
  def load_table_context
    @users = User.order(id: :desc).limit(10)
    @certifications_on_space =
      proc do |user, space_id|
        user
          .certifications
          .joins(:training, training: :spaces)
          .where(trainings: { spaces: { id: space_id } })
      end
    @all_user_certs = proc { |user| user.certifications }
  end

  # What an empty room reports: the same keys as latest_sign_in_details. The
  # request spec that compares the keys of an empty and an occupied room keeps the
  # two in step.
  EMPTY_SIGN_IN_DETAILS = {
    users: [], certification: [], has_membership: false,
    expiration_date: "", is_student: false, signed_sheet: false
  }.freeze

  # The most recent sign-in's details, which the tap-in modal reads.
  def latest_sign_in_details(signed_in_users)
    latest = signed_in_users.first
    return EMPTY_SIGN_IN_DETAILS unless latest

    {
      users: signed_in_users.map { |user| [user.name, user.email, user.username] },
      certification: Certification.select("certifications.id, certifications.user_id, trainings.name_en")
        .joins(:training).where(user_id: latest.id).group_by(&:user_id).to_a,
      has_membership: latest.has_active_membership?,
      expiration_date: latest.memberships.active.order(end_date: :desc).first&.end_date&.to_date || "",
      is_student: latest.student?,
      signed_sheet: latest.walk_in_safety_sheets.any?
    }
  end

  def update_lab_session
    current_sesh =
      current_user.lab_sessions.where("sign_out_time > ?", Time.zone.now).last
    return unless current_sesh.present?
      current_sesh.sign_out_time = Time.zone.now
      current_sesh.save
    
  end
end
