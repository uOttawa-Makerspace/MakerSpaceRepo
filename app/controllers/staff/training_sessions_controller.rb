# frozen_string_literal: true

class Staff::TrainingSessionsController < StaffDashboardController
  layout "staff_area"
  before_action :current_training_session, except: %i[new create index]
  before_action :changed_params, only: [:update]
  before_action :verify_ownership, except: %i[new create index]
  before_action :set_courses_and_levels, only: %i[new show]

  def index
    respond_to do |format|
      format.html
      format.json do
        render json:
                 TrainingSession.where(user_id: @user.id).as_json(
                   include: %i[training space certifications]
                 )
      end
    end
  end

  def new
    respond_to do |format|
      format.html { @new_training_session = TrainingSession.new }
      format.json do
        render json: {
                 trainings: @space.trainings.pluck(:id, :name_en).as_json,
                 level: @levels.as_json,
                 course_names: @course_names.as_json,
                 admins:
                   User.where(role: %w[staff admin]).pluck(:id, :name).as_json,
                 users: @space.signed_in_users.pluck(:id, :name, :email).as_json
               }
      end
    end
  end

  def create
    @new_training_session = TrainingSession.new(default_params)
    course_name = CourseName.find_by(name: @new_training_session.course)
    @new_training_session.course_name = course_name if course_name.present?
    if @new_training_session.save
      respond_to do |format|
        format.html do
          redirect_to staff_training_session_path(@new_training_session.id)
        end
        format.json do
          render json: { id: @new_training_session.id, created: true }
        end
      end
    else
      respond_to do |format|
        format.html do
          redirect_back(
            fallback_location: root_path,
            alert: "Something went wrong. Please try again."
          )
        end
        format.json { render json: { created: false } }
      end
    end
  end

  def show
  end

  def update
    if changed_params["user_id"].present? && !@user.admin?
        flash[:alert] = "You're not an admin."
        redirect_back(fallback_location: root_path) and return
      end

    @current_training_session.update(changed_params)

    if params["dropped_users"].present?
      @current_training_session.users -=
        User.where(username: params["dropped_users"])
      User
        .where(username: params["dropped_users"])
        .each do |user|
          cert =
            user.certifications.find_by(
              training_session_id: @current_training_session.id
            )
          next if cert.blank?

          next if cert.destroy
          flash[
            :alert
          ] = "Error deleting #{user.username}'s #{@current_training_session.training.name_en} certification."
        end
    end

    @current_training_session.users +=
      User.where(username: params["added_users"]) if params[
      "added_users"
    ].present?
    @current_training_session.users = @current_training_session.users.uniq

    course_name = CourseName.find_by(name: @current_training_session.course)
    @current_training_session.course_name = course_name if course_name.present?

    if @current_training_session.save
      flash[:notice] = "Training session updated succesfully"
    else
      flash[:alert] = "Something went wrong, please try again"
    end
    redirect_back(fallback_location: root_path)
  end

  def certify_trainees
    error = false
    duplicates = 0
    @current_training_session.users.each do |graduate|
      # Skip if user already has a certifications that match the training id and training level
      if graduate
           .certifications
           .where(
             training_session_id:
               TrainingSession.where(
                 training_id: @current_training_session.training_id,
                 level: @current_training_session.level
               ).pluck(:id)
           )
           .present?
        duplicates += 1
        next
      end
      certification =
        Certification.new(
          user_id: graduate.id,
          training_session_id: @current_training_session.id
        )
      next if certification.save
      error = true
      flash[
        :alert
      ] = "#{graduate.username}'s certification has not saved properly!"
    end
    respond_to do |format|
      format.html do
        redirect_to staff_dashboard_index_path,
                    notice:
                      "Training Session Completed Successfully" +
                        (
                          if duplicates > 0
                            " (#{duplicates} duplicates skipped)"
                          else
                            ""
                          end
                        )
      end
      format.json { render json: { certified: !error } }
    end
  end

  def revoke_certification
    cert = Certification.find(params[:cert_id])
    if cert.destroy
      flash[:notice] = "Deleted Successfully"
    else
      flash[:alert] = "Something went wrong, try refreshing"
    end
    redirect_to user_path(cert.user.username)
  end

  def destroy
    if @current_training_session.destroy
      flash[:notice] = "Deleted Successfully"
      redirect_to staff_dashboard_index_path
    else
      flash[:alert] = "Something went wrong"
      redirect_back(fallback_location: root_path)
    end
  end

  def training_report
    respond_to do |format|
      format.html
      format.xlsx do
        send_data ReportGenerator
                    .generate_training_session_report(params[:id])
                    .to_stream
                    .read
      end
    end
  end

  private

  def default_params
    if params[:user_id].present?
      if @user.admin?
        {
          user_id: params[:user_id],
          training_id: params[:training_id],
          course: params[:course],
          space_id: params[:training_session][:space_id],
          level: params[:level],
          user_ids: params["training_session_users"]
        }
      end
    else
      {
        user_id: current_user.id,
        training_id: params[:training_id],
        course: params[:course],
        space_id: params[:training_session][:space_id],
        level: params[:level],
        user_ids: params["training_session_users"]
      }
    end
  end

  def training_session_params
    params.require(:training_session).permit(
      :training_id,
      :course,
      :users,
      :space_id
    )
  end

  def current_training_session
    @current_training_session = TrainingSession.find(params[:id])
    @staff = User.find(@current_training_session.user_id)
  end

  def changed_params
    params
      .require(:changed_params)
      .permit(:training_id, :course, :user_id, :level)
      .reject { |_, v| v.blank? }
  end

  def verify_ownership
    return if @user.admin? || @current_training_session.user == @user
      flash[:alert] = "Can't access training session"
      redirect_to new_staff_training_session_path
    
  end

  def set_courses_and_levels
    @course_names = CourseName.pluck(:name)
    @levels ||= TrainingSession.new.levels
  end
end
