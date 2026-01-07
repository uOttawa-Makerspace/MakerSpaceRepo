# frozen_string_literal: true

class Admin::UsersController < AdminAreaController
  before_action :load_user, only: %i[show edit update]
  before_action :require_admin, only: %i[delete_user restore_user toggle_lock_user set_role manage_roles]

  layout "admin_area"

  # Whitelist for sortable columns to prevent SQL injection
  SORTABLE_COLUMNS = {
    'username' => 'users.username',
    'name' => 'users.name',
    'sign_in_time' => 'lab_sessions.sign_in_time',
    'created_at' => 'users.created_at'
  }.freeze

  SORT_DIRECTIONS = %w[asc desc].freeze

  SEARCHABLE_FILTERS = %w[Name Email Username].freeze

  ASSIGNABLE_ROLES = %w[admin staff regular_user volunteer].freeze

  def index
    unless valid_sort_params?
      redirect_to admin_users_path, alert: "Invalid parameters!"
      return
    end

    case params[:p]
    when "signed_in_users"
      load_signed_in_users
    when "new_users", nil
      load_new_users
    else
      redirect_to admin_users_path, alert: "Invalid parameters!"
    end
  end

  def search
    unless valid_sort_params?
      redirect_to admin_users_path, alert: "Invalid parameters!"
      return
    end

    unless params[:q].present?
      redirect_back(fallback_location: root_path, alert: "Invalid parameters!")
      return
    end

    @query = params[:q]
    @users = search_users(@query, params[:filter])
  end

  def show
    @all_sessions = @edit_admin_user.lab_sessions.order(sign_in_time: :desc)
    calculate_average_session_time
    @certifications = @edit_admin_user.certifications.order(Arel.sql("lower(name) ASC"))
  end

  def edit
    @rfids = Rfid.recent_unset
    @certifications = @edit_admin_user.certifications.order(Arel.sql("lower(name) ASC"))
  end

  def update
    @edit_admin_user.certifications.destroy_all
    
    # Handle RFID assignment separately
    assign_rfid_if_present
    
    if @edit_admin_user.update(user_params)
      create_certifications
      redirect_to edit_admin_user_path(@edit_admin_user), notice: "User information updated!"
    else
      @rfids = Rfid.recent_unset
      @certifications = @edit_admin_user.certifications.order(Arel.sql("lower(name) ASC"))
      render :edit
    end
  end

  def delete_repository
    Repository.find(params[:id]).destroy
    redirect_to root_path, notice: "Repository Deleted!"
  end

  def delete_user
    unless @user.admin? && @user.pword == params[:password]
      redirect_to user_path(User.find(params[:id]).username), alert: "Invalid password!"
      return
    end

    delete_user = User.find(params[:id])
    soft_delete_user(delete_user)
    redirect_to root_path, notice: "User flagged as deleted"
  end

  def restore_user
    restore_user = User.unscoped.find(params[:id])
    restore_user_account(restore_user)
    redirect_to user_path(restore_user.username), notice: "User restored!"
  end

  def toggle_lock_user
    user_to_toggle = User.find(params[:id])
    toggle_user_lock_status(user_to_toggle)
    redirect_to user_path(user_to_toggle.username),
                notice: "User #{user_to_toggle.locked ? 'locked' : 'unlocked'}!"
  end

  def set_role
    update_user_roles if valid_role_update_params?
    update_user_staff_spaces if params[:spaces].present?

    respond_to do |format|
      format.html { redirect_back(fallback_location: root_path) }
      format.json { head :ok }
      format.js { render layout: false }
      format.all { redirect_back(fallback_location: root_path) }
    end
  end

  def manage_roles
    @admins = User.where(role: "admin").order(Arel.sql("lower(name) ASC"))
    @staff = User.where(role: "staff").order(Arel.sql("lower(name) ASC"))
    @volunteers = User.joins(:programs)
                      .where(programs: { program_type: Program::VOLUNTEER })
                      .order(Arel.sql("lower(name) ASC"))
    @roles = ASSIGNABLE_ROLES
    @space_list = Space.all

    @admin_spaces = build_user_spaces_hash(@admins)
    @staff_spaces = build_user_spaces_hash(@staff)
  end

  def rename_user
    user = User.find(params[:id])
    
    unless params[:rename].present?
      redirect_to user_path(user.username), alert: "No username provided"
      return
    end

    if user.update(username: params[:rename])
      flash[:notice] = "User renamed successfully"
    else
      flash[:alert] = "Username invalid: #{user.errors.full_messages.join(', ')}"
    end
    
    redirect_to user_path(user.reload.username)
  end

  private

  # ============================================
  # Authorization
  # ============================================

  def require_admin
    return if @user&.admin?
    
    redirect_to root_path, alert: "You do not have permission to do that!"
  end

  # ============================================
  # Parameter Validation
  # ============================================

  def valid_sort_params?
    return true if params[:sort].blank? && params[:direction].blank?
    
    safe_sort_column.present? && SORT_DIRECTIONS.include?(params[:direction])
  end

  def safe_sort_column
    # Map user-provided sort param to safe column name
    SORTABLE_COLUMNS[params[:sort]&.gsub(/^(users\.|lab_sessions\.)/, '')]
  end

  def safe_order_clause
    column = safe_sort_column
    direction = SORT_DIRECTIONS.include?(params[:direction]) ? params[:direction].to_sym : :desc

    return nil unless column

    [column, direction]
  end

  def valid_role_update_params?
    params[:role].present? && 
      params[:user_ids].is_a?(Array) && 
      ASSIGNABLE_ROLES.include?(params[:role])
  end

  # ============================================
  # Strong Parameters
  # ============================================

  # SECURITY FIX: Removed :role from permitted params
  # Role changes should only happen through set_role action with proper authorization
  def user_params
    params.require(:user).permit(:gender, :faculty, :use)
  end

  # ============================================
  # User Loading
  # ============================================

  def load_user
    @edit_admin_user = User.find(params[:id])
  end

  def load_signed_in_users
    # Set default sort for signed in users
    if params[:sort].blank? && params[:direction].blank?
      params[:sort] = "sign_in_time"
      params[:direction] = "desc"
    end

    @users_temp = LabSession.joins(:user).where("sign_out_time > ?", Time.zone.now)
    
    # SECURITY FIX: Use parameterized query instead of string interpolation
    if params[:location].present?
      @users_temp = @users_temp.joins(sanitized_pi_readers_join)
                               .where("LOWER(pi_readers.pi_location) = LOWER(?)", params[:location])
    end

    if (order_clause = safe_order_clause)
      column, direction = order_clause
      @users_temp = @users_temp.order(column => direction)
    else
      @users_temp = @users_temp.order(lab_sessions: { sign_in_time: :desc })
    end
    @users_temp = @users_temp.paginate(page: params[:page], per_page: 20)
    
    @users = @users_temp.includes(:user).map(&:user)
    @total_pages = @users_temp.total_pages
  end

  def load_new_users
    # Set default sort for new users
    if params[:sort].blank? && params[:direction].blank?
      params[:sort] = "created_at"
      params[:direction] = "desc"
    end

    order_clause = safe_order_clause || "users.created_at desc"
    @users = User.includes(:lab_sessions)
                 .order(Arel.sql(order_clause))
                 .paginate(page: params[:page], per_page: 20)
    @total_pages = @users.total_pages
  end

  # SECURITY FIX: Safe join without user input in SQL string
  def sanitized_pi_readers_join
    "INNER JOIN pi_readers ON lab_sessions.pi_mac_address = pi_readers.mac_address"
  end

  # ============================================
  # Search
  # ============================================

  def search_users(query, filter)
    # Sanitize query for LIKE to prevent SQL injection
    sanitized_query = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    order_clause = safe_order_clause || "users.created_at desc"
    
    base_scope = User.includes(:lab_sessions)
    
    scope = case filter
            when "Name"
              base_scope.where("LOWER(name) LIKE LOWER(?)", sanitized_query)
            when "Email"
              base_scope.where("LOWER(email) LIKE LOWER(?)", sanitized_query)
            when "Username"
              base_scope.where("LOWER(username) LIKE LOWER(?)", sanitized_query)
            else
              base_scope.where(
                "LOWER(name) LIKE LOWER(:q) OR LOWER(email) LIKE LOWER(:q) OR LOWER(username) LIKE LOWER(:q)",
                q: sanitized_query
              )
            end
    
    scope.order(Arel.sql(order_clause)).paginate(page: params[:page], per_page: 20)
  end

  # ============================================
  # Session Calculations
  # ============================================

  def calculate_average_session_time
    total_minutes = 0
    session_count = 0

    @all_sessions.each do |session|
      next if session.blank?

      end_time = session.sign_out_time < Time.zone.now ? session.sign_out_time : Time.zone.now
      total_minutes += (end_time - session.sign_in_time) / 60
      session_count += 1
    end

    @average_time = session_count > 0 ? (total_minutes / session_count).round : 0
  end

  # ============================================
  # RFID Assignment
  # ============================================

  def assign_rfid_if_present
    return unless params[:user][:rfid].present?
    
    rfid = Rfid.find_by(id: params[:user][:rfid])
    return unless rfid
    
    @edit_admin_user.rfid&.destroy!
    rfid.update!(user: @edit_admin_user)
  end

  # ============================================
  # Certifications
  # ============================================

  def create_certifications
    return unless params["certifications"].present?
    
    params["certifications"].first(5).each do |cert_name|
      Certification.create(name: cert_name, user_id: @edit_admin_user.id)
    end
  end

  # ============================================
  # User Management
  # ============================================

  def soft_delete_user(user)
    user.transaction do
      user.deleted = true
      user.repositories.update_all(deleted: true)
      LabSession.where(user_id: user.id).destroy_all
      Certification.where(user_id: user.id).destroy_all
      user.save!
    end
  end

  def restore_user_account(user)
    user.transaction do
      user.deleted = false
      user.repositories.update_all(deleted: false)
      user.save!
    end
  end

  def toggle_user_lock_status(user)
    user.locked = !user.locked
    user.locked_until = user.locked ? 99.years.from_now : nil
    user.auth_attempts = user.locked ? 5 : 0
    user.save!
  end

  # ============================================
  # Role Management
  # ============================================

  def update_user_roles
    # SECURITY: Validate role before assignment
    return unless ASSIGNABLE_ROLES.include?(params[:role])
    
    # SECURITY: Validate user_ids are integers
    user_ids = params[:user_ids].map(&:to_i).reject(&:zero?)
    
    User.where(id: user_ids).find_each do |user|
      # Audit log for role changes
      Rails.logger.info "[ROLE_CHANGE] User##{user.id} role changed from '#{user.role}' to '#{params[:role]}' by Admin##{@user.id}"
      user.update(role: params[:role])
    end
  end

  def update_user_staff_spaces
    params[:spaces].each do |user_id, space_ids|
      user = User.find_by(id: user_id)
      next unless user&.staff?

      space_list = Array(space_ids).map(&:to_i).reject(&:zero?)
      
      # Create new staff spaces
      space_list.each do |space_id|
        StaffSpace.find_or_create_by(space_id: space_id, user: user)
      end
      
      # Remove spaces not in the list
      user.staff_spaces.where.not(space_id: space_list).destroy_all
    end
    
    flash[:notice] = "Successfully changed spaces for the user(s)."
  end

  def build_user_spaces_hash(users)
    users.each_with_object({}) do |user, hash|
      hash[user.id] = user.staff_spaces.pluck(:space_id)
    end
  end
end