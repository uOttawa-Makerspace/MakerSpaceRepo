# frozen_string_literal: true

class StaffDashboardController < StaffAreaController
  # The only user fields the search JSON sends (what the staff app reads, plus id).
  SEARCH_JSON_FIELDS = %i[id name username email].freeze

  # NOTE: @space is set by StaffAreaController, and is always a space the user may work in.
  before_action :require_space, only: %i[
    index refresh_capacity refresh_tables import_excel sign_out_users add_signed_in_users_to_teams
    sign_out_all_users sign_in_users search present_users_report
  ]
  
  def index
    # Strict loading because this is used in table views
    # FIXME: Temporarily disabled because of space 119
    @signed_in_users = @space.including_walk_in_sheets(
      User
        .where(id: LabSession.active.where(space: @space).select(:user_id))
        .includes(certifications: {training_session: [:training, :user]})
        .includes(:lab_sessions)
    )

    respond_to do |format|
      format.html do
        @signed_out_users = @space.recently_signed_out_users_with_history
        load_table_context
        @table_column_count = 0
      end
      format.json do
        signed_in_user_ids = @space.signed_in_users.map(&:id)
        users_with_certs = User
          .where(id: signed_in_user_ids)
          .includes(certifications: { training_session: :training })
        with_membership = Membership.active.where(user_id: signed_in_user_ids).reorder(nil).distinct.pluck(:user_id)
        with_sheet = WalkInSafetySheet.where(user_id: signed_in_user_ids).distinct.pluck(:user_id)

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
                    "signed_safety_sheet" => with_sheet.include?(u.id),
                    "membership_status" => with_membership.include?(u.id)
                  }
                )
              end
              .as_json,
          space_list: @all_spaces.pluck(:name, :id)
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
    return head :not_modified if params[:token] == signed_in_users.map(&:id).join(",")

    load_table_context
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
    file = params[:file]
    return refuse_import(:no_file) if file.blank?
    unless IMPORT_EXTENSIONS.include?(File.extname(file.original_filename))
      return refuse_import(:file_type, name: file.original_filename)
    end

    faulty_user_data = sign_in_listed_users(read_spreadsheet(file))
    flash[:notice] = I18n.t("staff_dashboard.flash.import_done")
    if faulty_user_data.any?
      flash[:alert_yellow] = I18n.t("staff_dashboard.flash.import_not_found", count: faulty_user_data.size)
      flash[:alert] = I18n.t("staff_dashboard.flash.import_errors", users: faulty_user_data.join(", "))
    end
    redirect_to staff_dashboard_index_path
  rescue Zip::Error, Roo::Error, Ole::Storage::FormatError
    # The file is not a readable spreadsheet of the type its name says.
    refuse_import(:unreadable)
  rescue StandardError => e
    report_unexpected(e, source: "staff_dashboard#import_excel")
    flash[:alert] = unexpected_error_message
    redirect_to staff_dashboard_index_path
  end

  # Signs each listed user out of their active sessions in the current space. Users who are not
  # signed in, and usernames that match no user, change nothing and are reported
  # back (flash for HTML; JSON lists signed_out, not_signed_in and not_found).
  def sign_out_users
    usernames = dropped_usernames
    users = User.where(username: usernames).to_a
    signed_out, not_signed_in = users.partition { |user| LabSession.sign_out(user, @space).positive? }
    # users.username is case-insensitive (citext), so compare the same way.
    found = users.map { |user| user.username.downcase }
    not_found = usernames.reject { |name| found.include?(name.downcase) }

    respond_to do |format|
      format.html do
        notes = []
        notes << I18n.t("staff_dashboard.flash.not_signed_in", names: not_signed_in.map(&:name).join(", ")) if not_signed_in.any?
        notes << I18n.t("staff_dashboard.flash.unknown_username", names: not_found.join(", ")) if not_found.any?
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
        Program.join(user, Program::TEAMS)
      end

      flash[:notice] = I18n.t("staff_dashboard.flash.added_to_teams")
    else
      flash[:alert] = I18n.t("staff_dashboard.flash.teams_not_here")
    end

    redirect_to staff_dashboard_index_path
  end

  def sign_out_all_users
    LabSession.sign_out_all(@space)
    respond_to do |format|
      format.html do
        redirect_to staff_dashboard_index_path(space_id: @space.id)
      end
      format.json { render json: { status: "ok" } }
    end
  end

  def sign_in_users
    # Staff dashboard changed, but we keep compat with app.
    user_query = params[:added_users] || params[:username]

    User.where(username: user_query).find_each { |user| LabSession.sign_in(user, @space) }

    respond_to do |format|
      format.html { redirect_to staff_dashboard_index_path(space_id: @space.id) }
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
    elsif !current_user.can_work_in?(new_space)
      http_status = :not_found
      message = "You are not assigned to that space"
    elsif current_user.update(space_id: new_space.id)
      @space = new_space
      flash[:notice] = I18n.t("staff_dashboard.flash.space_changed")
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
    error, http_status = link_rfid_error

    respond_to do |format|
      format.html do
        if error
          flash[:alert] = I18n.t("staff_dashboard.flash.rfid_not_linked", error: error)
        else
          flash[:notice] = I18n.t("staff_dashboard.flash.rfid_linked")
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
    outcome, error, http_status = unlink_rfid_result

    respond_to do |format|
      format.html do
        if error
          flash[:alert] = error
        elsif outcome == :already_unlinked
          flash[:notice] = I18n.t("staff_dashboard.flash.rfid_already_unlinked")
        else
          flash[:notice] = I18n.t("staff_dashboard.flash.rfid_unlinked")
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
      flash[:alert] = I18n.t("staff_dashboard.flash.select_valid_user")
      redirect_to staff_dashboard_index_path
    end
  end

  def search
    return reject_blank_search if params[:query].blank? && params[:username].blank?

    if params[:username].present?
      @users = User.where("username = ?", params[:username])
    else
      @query = params[:query]
      @users = User.text_search(@query).order(:updated_at)
    end
    respond_to do |format|
      format.html { @users = @users.includes(:lab_sessions) if @query.present? }
      format.json { render json: @users.as_json(only: SEARCH_JSON_FIELDS) }
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
                    "#{@space.name}_#{Time.current.strftime("%Y-%m-%d_%Hh%M")}_present_users_report.xlsx"
      end
    end
  end

  def populate_users
    json_data = User.fuzzy_search(params[:search]).as_json(only: %i[name username])
    render json: { users: json_data }
  end

  private

  # A search with neither a query nor a username: the page goes back to the dashboard, the staff app gets an error object.
  def reject_blank_search
    respond_to do |format|
      format.html { redirect_to staff_dashboard_index_path, alert: I18n.t("staff_dashboard.flash.no_search_parameters") }
      format.json { render json: { error: "no params" } }
    end
  end

  # Returns [error, status]; error is nil when the card was linked.
  def link_rfid_error
    if params[:user_id].blank? || params[:card_number].blank?
      return ["card_number and user_id are required", :unprocessable_content]
    end

    card_number = params[:card_number]
    user = User.find_by(id: params[:user_id].to_s.match?(/\A\d+\z/) ? params[:user_id] : nil)
    return ["user not found", :not_found] if user.nil?
    return ["card number is invalid", :unprocessable_content] unless Rfid.valid_card_number?(card_number)

    [Rfid.link_to_user!(card_number, user), :unprocessable_content]
  end

  # Returns [outcome, error, status]; error is nil when the card was handled.
  def unlink_rfid_result
    if params[:card_number].blank?
      return [nil, "card_number is required", :unprocessable_content]
    end

    outcome = Rfid.unlink_card!(params[:card_number].to_s, actor: current_user)
    return [outcome, "RFID card not found", :not_found] if outcome == :not_found

    [outcome, nil, nil]
  rescue Rfid::OwnerChanging
    [nil, I18n.t("errors.staff.dashboard.card_changing"), :conflict]
  end

  # An array of strings, or a single string, is accepted; blanks, hashes and repeats are ignored.
  def dropped_usernames
    dropped = params[:dropped_users]
    dropped = [dropped] if dropped.is_a?(String)
    return [] unless dropped.is_a?(Array)

    dropped.grep(String).map(&:strip).reject(&:blank?).uniq(&:downcase)
  end

  IMPORT_EXTENSIONS = %w[.xls .xlsx].freeze

  def refuse_import(cause, **options)
    flash[:alert] = I18n.t("errors.staff.dashboard.import_#{cause}", **options)
    redirect_to staff_dashboard_index_path
  end

  def read_spreadsheet(file)
    if File.extname(file.original_filename) == ".xls"
      Roo::Excel.new(file.path)
    else
      Roo::Excelx.new(file.path)
    end
  end

  # Signs in the user named on each row (by email, name or username, first column) for the standard session length;
  # returns the cell values that matched no user.
  def sign_in_listed_users(spreadsheet)
    not_found = []
    (1..spreadsheet.last_row).each do |i|
      user_data = spreadsheet.row(i)[0].to_s.downcase
      next if user_data.blank?

      user = User.where("lower(email) = ? OR lower(name) = ? OR lower(username) = ?", user_data, user_data, user_data)
      if user.blank?
        not_found << user_data
        next
      end
      LabSession.sign_in(user.last, @space)
    end
    not_found
  end

  # What the table partials (refresh_tables, the sign out JS response) read.
  def load_table_context
    @users = User.includes(:lab_sessions).order(id: :desc).limit(10)
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
      signed_sheet: WalkInSafetySheet.exists?(user_id: latest.id)
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
