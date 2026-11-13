# frozen_string_literal: true

class Staff::TrainingSessionsController < StaffDashboardController
  layout "staff_area"
  before_action :current_training_session, except: %i[new create index]
  before_action :changed_params, only: [:update]
  before_action :verify_ownership, except: %i[new create index]
  before_action :refuse_locked_changes, only: [:update]
  before_action :set_courses_and_levels, only: %i[new show]

  def index
    scope = TrainingSession.where(user_id: @user.id).order(created_at: :desc)
    @pagy, @sessions = pagy(scope, limit: 50)

    respond_to do |format|
      format.html
      format.json do
        render json:
                TrainingSession.where(user_id: @user.id).as_json(
                  include: {
                    training: {},
                    space: {},
                    certifications: {},
                    users: { only: %i[id username name email role] }
                  }
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
    return refuse_creation(I18n.t("errors.staff.training_sessions.instructor_not_assignable")) unless @new_training_session.instructor_assignable_by?(@user)

    if @new_training_session.open_by(@user)
      respond_to do |format|
        format.html do
          redirect_to staff_training_session_path(@new_training_session.id)
        end
        format.json do
          render json: { id: @new_training_session.id, created: true }
        end
      end
    else
      refuse_creation(validation_message(@new_training_session, "errors.staff.training_sessions.not_created"))
    end
  end

  def show
  end

  def update
    if changed_params["user_id"].present? && !@user.admin?
      flash[:alert] = "You're not an admin."
      redirect_back(fallback_location: root_path) and return
    end

    result =
      @current_training_session.update_roster(
        changed_params,
        added: Array(params["added_users"]),
        dropped: Array(params["dropped_users"]),
        by: @user
      )
    if result.saved?
      flash[:notice] = "Training session updated succesfully"
      flash_certification_failure(result.failed_certifications.last)
    else
      flash[:alert] = validation_message(@current_training_session, "errors.staff.training_sessions.not_updated")
    end
    redirect_back(fallback_location: root_path)
  end

  def certify_trainees
    result = @current_training_session.certify_trainees!
    error = !result.certified?
    duplicates = result.duplicates
    if error
      flash[:alert] = "#{result.failed.last.username}'s certification has not saved properly!"
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
                        ) +
                        (result.self_skipped ? " (you can't certify yourself)" : "")
      end
      format.json { render json: { certified: !error } }
    end
  end

  def revoke_certification
    cert = @current_training_session.certifications.find(params[:cert_id])
    if cert.deactivate(@user)
      flash[:notice] = "Revoked Successfully"
    else
      flash[:alert] = validation_message(cert, "errors.staff.training_sessions.certification_not_revoked")
    end
    redirect_to user_path(cert.user.username)
  end

  def destroy
    if @current_training_session.destroy
      flash[:notice] = "Deleted Successfully"
      redirect_to staff_dashboard_index_path
    else
      flash[:alert] = validation_message(@current_training_session, "errors.staff.training_sessions.not_deleted")
      redirect_back(fallback_location: root_path)
    end
  end

  def training_report
    respond_to do |format|
      format.xlsx do
        send_data ReportGenerator
                    .generate_training_session_report(params[:id])
                    .to_stream
                    .read
      end
    end
  end

  private

  def refuse_creation(message)
    respond_to do |format|
      format.html { redirect_back(fallback_location: root_path, alert: message) }
      format.json { render json: { created: false, error: message, reference: error_reference } }
    end
  end

  # The instructor is the user named by the form (the React app always sends one), or the current user.
  # `TrainingSession#instructor_assignable_by?` decides whether the current user may name them.
  def default_params
    {
      user_id: params[:user_id].presence || current_user.id,
      training_id: params[:training_id],
      course: params[:course],
      space_id: params[:training_session][:space_id],
      level: params[:level],
      user_ids: params["training_session_users"]
    }
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
    @staff = @current_training_session.user || raise(ActiveRecord::RecordNotFound)
  end

  def changed_params
    params
      .require(:changed_params)
      .permit(:training_id, :course, :user_id, :level)
      .reject { |_, v| v.blank? }
  end

  def flash_certification_failure(user)
    return if user.blank?

    flash[:alert] = "Error removing #{user.username}'s #{@current_training_session.training.name_en} certification."
  end

  def refuse_locked_changes
    return unless @current_training_session.locked_change?(changed_params)

    flash[:alert] = I18n.t("errors.staff.training_sessions.locked_once_awarded")
    redirect_back(fallback_location: root_path)
  end

  def verify_ownership
    return if @current_training_session.editable_by?(@user)

    flash[:alert] = "Can't access training session"
    redirect_to new_staff_training_session_path
  end

  def set_courses_and_levels
    @course_names = CourseName.pluck(:name)
    @levels ||= TrainingSession.new.levels
  end
end
