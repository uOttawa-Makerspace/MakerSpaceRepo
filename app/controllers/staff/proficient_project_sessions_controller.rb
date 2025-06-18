class Staff::ProficientProjectSessionsController < StaffDashboardController
  layout "staff_area"
  before_action :changed_params, only: [:update]

  def index
    respond_to do |format|
      format.html
      format.json do
        render json:
                 ProficientProjectSession.where(user_id: @user.id).as_json(
                   include: %i[training space certifications]
                 )
      end
    end
  end

  def new
    respond_to do |format|
      format.html { @new_proficient_project_session = ProficientProjectSession.new }
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
    @new_proficient_project_session = ProficientProjectSession.new(default_params)
    if @new_proficient_project_session.save
      respond_to do |format|
        format.html do
          redirect_to staff_proficient_project_session_path(@new_proficient_project_session.id)
        end
        format.json do
          render json: { id: @new_proficient_project_session.id, created: true }
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
    @current_proficient_project_session = ProficientProjectSession.find(params[:id])
  end

  def update
    if changed_params["user_id"].present? && !@user.admin?
        flash[:alert] = "You're not an admin."
        redirect_back(fallback_location: root_path) and return
      end

    @current_proficient_project_session.update(changed_params)

    if params["dropped_user"].present?
      @current_proficient_project_session.user -=
        User.where(username: params["dropped_users"])
      user = User
        .where(username: params["dropped_users"])
      cert = Certification.find(@current_proficient_project_session.certification_id)
      cert.destroy
      #this needs a new error message if the cert could not be destroyed
    end

    @current_proficient_project_session.users +=
      User.where(username: params["added_users"]) if params[
      "added_users"
    ].present?
    @current_proficient_project_session.users = @current_proficient_project_session.users.uniq

    course_name = CourseName.find_by(name: @current_proficient_project_session.course)
    @current_proficient_project_session.course_name = course_name if course_name.present?

    if @current_proficient_project_session.save
      flash[:notice] = "Training session updated succesfully"
    else
      flash[:alert] = "Something went wrong, please try again"
    end
    redirect_back(fallback_location: root_path)
  end

  def certify_participant
    @current_proficient_project_session = ProficientProjectSession.find(params[:proficient_project_session_id])
    error = false
    duplicates = 0
    graduate = @current_proficient_project_session.user
      # Skip if user already has a certifications that match the training id and training level
      if graduate
           .certifications
           .where(
             training_session_id:
               TrainingSession.where(
                 training_id: @current_proficient_project_session.proficient_project.training_id,
                 level: @current_proficient_project_session.level
               ).pluck(:id)
           )
           .present?
        duplicates += 1
      end
      certification =
        Certification.new(
          user_id: graduate.id,
          training_session_id: nil
        )
    if certification.save
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
    if @current_proficient_project_session.destroy
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

  def proficient_project_session_params
    params.require(:proficient_project_session).permit(
      :certification_id,
      :proficient_project_id,
      :level,
      :user_id
    )
  end

  def current_proficient_project_session
    @current_proficient_project_session = ProficientProjectSession.find(params[:id])
  end


  def set_levels
    @levels ||= ProficientProjectSession.new.levels
  end
end
