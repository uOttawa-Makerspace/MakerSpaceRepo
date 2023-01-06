# frozen_string_literal: true

class Admin::UsersController < AdminAreaController
  before_action :load_user, only: %i[show edit update]

  layout "admin_area"

  def index
    if sort_params
      if params[:p] == "signed_in_users"
        if params[:sort].blank? && params[:direction].blank?
          params[:sort] = "lab_sessions.sign_in_time"
          params[:direction] = "desc"
        end
        @users_temp =
          LabSession.joins(:user).where("sign_out_time > ?", Time.zone.now)
        if params[:location].present?
          @users_temp =
            @users_temp.joins(
              "INNER JOIN pi_readers ON pi_mac_address = mac_address AND LOWER(pi_location) = LOWER('#{params[:location]}')"
            )
        end
        @users_temp =
          @users_temp.order("#{params[:sort]} #{params[:direction]}").paginate(
            page: params[:page],
            per_page: 20
          )
        @users = @users_temp.includes(:user).map(&:user)
        @total_pages = @users_temp.total_pages
      elsif params[:p] == "new_users" || params[:p].blank?
        if params[:sort].blank? && params[:direction].blank?
          params[:sort] = "users.created_at"
          params[:direction] = "desc"
        end
        @users =
          User
            .includes(:lab_sessions)
            .order("#{params[:sort]} #{params[:direction]}")
            .paginate(page: params[:page], per_page: 20)
        @total_pages = @users.total_pages
      else
        redirect_to admin_users_path
        flash[:alert] = "Invalid parameters!"
      end
    else
      redirect_to admin_users_path
      flash[:alert] = "Invalid parameters!"
    end
  end

  def sort_params
    if (
         (
           %w[
             username
             name
             lab_sessions.sign_in_time
             users.created_at
           ].include? params[:sort]
         ) && (%w[desc asc].include? params[:direction])
       ) || (params[:sort].blank? && params[:direction].blank?)
      true
    end
  end

  def search
    if sort_params
      if params[:q].present?
        @query = params[:q]
        if params[:filter] == "Name"
          @users =
            User
              .where("LOWER(name) like LOWER(?)", "%#{@query}%")
              .includes(:lab_sessions)
              .order(Arel.sql("#{params[:sort]} #{params[:direction]}"))
              .paginate(page: params[:page], per_page: 20)
        elsif params[:filter] == "Email"
          @users =
            User
              .where("LOWER(email) like LOWER(?)", "%#{@query}%")
              .includes(:lab_sessions)
              .order(Arel.sql("#{params[:sort]} #{params[:direction]}"))
              .paginate(page: params[:page], per_page: 20)
        elsif params[:filter] == "Username"
          @users =
            User
              .where("LOWER(username) like LOWER(?)", "%#{@query}%")
              .includes(:lab_sessions)
              .order(Arel.sql("#{params[:sort]} #{params[:direction]}"))
              .paginate(page: params[:page], per_page: 20)
        elsif params[:filter].blank?
          @users =
            User
              .where(
                "LOWER(name) like LOWER(?) OR LOWER(email) like LOWER(?) OR LOWER(username) like LOWER(?)",
                "%#{@query}%",
                "%#{@query}%",
                "%#{@query}%"
              )
              .includes(:lab_sessions)
              .order(Arel.sql("#{params[:sort]} #{params[:direction]}"))
              .paginate(page: params[:page], per_page: 20)
        end
      else
        redirect_back(fallback_location: root_path)
        flash[:alert] = "Invalid parameters!"
      end
    else
      redirect_to admin_users_path
      flash[:alert] = "Invalid parameters!"
    end
  end

  def show
    @all_sessions = @edit_admin_user.lab_sessions.order("sign_in_time DESC")
    each_session = 0
    count = 0
    @all_sessions.each do |session|
      next if session.blank?

      each_session =
        if session.sign_out_time < Time.zone.now
          each_session + (session.sign_out_time - session.sign_in_time) / 60
        else
          each_session + (Time.zone.now - session.sign_in_time) / 60
        end
      count += 1
    end
    @average_time = (count > 0 ? (each_session / count).round : each_session)
    @certifications = @edit_admin_user.certifications.order("lower(name) ASC")
  end

  def edit
    @rfids = Rfid.recent_unset
    @certifications = @edit_admin_user.certifications.order("lower(name) ASC")
  end

  def update
    @edit_admin_user.certifications.destroy_all
    @edit_admin_user.update!(user_params)
    if params[:user][:rfid].present? &&
         (rfid = Rfid.where("id = ?", params[:user][:rfid]).first)
      @edit_admin_user.rfid&.destroy!
      rfid.user = @edit_admin_user
      rfid.save!
    end
    if @edit_admin_user.update(user_params)
      create_certifications
      redirect_to edit_admin_user_path(@edit_admin_user),
                  notice: "User information updated!"
    end
  end

  def delete_repository
    Repository.find(params[:id]).destroy
    redirect_to root_path, notice: "Repository Deleted!"
  end

  def delete_user
    if @user.admin? && @user.pword == params[:password]
      delete_user = User.find(params[:id])
      delete_user.deleted = true
      delete_user.repositories.each do |repo|
        repo.deleted = true
        repo.save!
      end
      delete_user.save!
      redirect_to root_path, notice: "User flagged as deleted"
    else
      redirect_to user_path(User.find(params[:id]).username),
                  alert: "Invalid password!"
    end
  end

  def restore_user
    if @user.admin?
      restore_user = User.unscoped.find(params[:id])
      restore_user.deleted = false
      restore_user.repositories.each do |repo|
        repo.deleted = false
        repo.save!
      end
      restore_user.save!
      redirect_to user_path(restore_user.username), notice: "User restored!"
    else
      redirect_to root_path, alert: "You do not have permission to do that!"
    end
  end

  def set_role
    @user = User.find(params[:id])
    @user.role = params[:role]
    @user.save

    @user.staff_spaces.destroy_all if params[:role] == "regular_user"
    @admins = User.where(role: "admin").order("lower(name) ASC")
    @staff = User.where(role: "staff").order("lower(name) ASC")
    @volunteers =
      User
        .joins(:programs)
        .where(programs: { program_type: Program::VOLUNTEER })
        .order("lower(name) ASC")
    @roles = %w[admin staff regular_user]
    # response is js
    respond_to do |format|
      format.html
      format.js { render layout: false }
      format.all { redirect_back(fallback_location: root_path) }
    end
  end

  def manage_roles
    @admins = User.where(role: "admin").order("lower(name) ASC")
    @staff = User.where(role: "staff").order("lower(name) ASC")
    @volunteers =
      User
        .joins(:programs)
        .where(programs: { program_type: Program::VOLUNTEER })
        .order("lower(name) ASC")
    @roles = %w[admin staff regular_user]
  end

  private

  def user_params
    params.require(:user).permit(:gender, :faculty, :use, :role)
  end

  def load_user
    @edit_admin_user = User.find(params[:id])
  end

  def create_certifications
    if params["certifications"].present?
      params["certifications"]
        .first(5)
        .each do |c|
          Certification.create(name: c, user_id: @edit_admin_user.id)
        end
    end
  end
end
