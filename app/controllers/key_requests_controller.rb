class KeyRequestsController < StaffAreaController
  layout "staff_area"

  before_action :check_key_request, only: %i[new create]
  before_action :set_key_request, only: %i[show steps]

  def index
    if @user.key_request.nil?
      redirect_to new_key_request_path
    elsif @user.key_request.status_in_progress?
      redirect_to key_request_steps_path(
                    key_request_id: @user.key_request.id,
                    step: 1
                  )
    else
      redirect_to key_request_path(@user.key_request.id)
    end
  end

  def show
    if !@user.eql?(@key_request.user) && !@user.admin?
      redirect_to staff_dashboard_index_path,
                  alert: "You don't have the permissions to view this"
    end

    @staff_certification = @key_request.staff_certification
  end

  def new
    @key_request = KeyRequest.new
  end

  def create
    @key_request =
      KeyRequest.new(
        key_request_params.merge(user_id: @user.id, status: :in_progress)
      )

    if @key_request.save
      redirect_to key_request_steps_path(
                    key_request_id: @key_request.id,
                    step: 2
                  )
    else
      flash[:alert] = "Something went wrong while trying to submit the form."
      render :new
    end
  end

  def steps
    @step = params[:step].present? ? params[:step].to_i : 1
    errors = []

    if params[:key_request].present?
      if params[:key_request][:read_lab_rules].present?
        params[:key_request][:read_lab_rules] = params[:key_request][
          :read_lab_rules
        ] == "true"
      end
      if params[:key_request][:read_policies].present?
        params[:key_request][:read_policies] = params[:key_request][
          :read_policies
        ] == "true"
      end
      if params[:key_request][:read_agreement].present?
        params[:key_request][:read_agreement] = params[:key_request][
          :read_agreement
        ] == "true"
      end

      unless @key_request.update(key_request_params)
        errors << "Failed to update key request"
      end
    end

    if errors.length > 0
      redirect_to key_request_steps_path(
                    key_request_id: @key_request.id,
                    step: @step == 1 ? 1 : (params[:step].to_i - 1)
                  ),
                  alert:
                    "An error occured while saving the key request at step #{params[:step]}: " +
                      errors.join(", ")
    else
      case @step
      when 1
        render "key_requests/wizard/personal_information"
      when 2
        render "key_requests/wizard/lab_rules"
      when 3
        render "key_requests/wizard/safety_questionnaire"
      when 4
        render "key_requests/wizard/policies"
      when 5
        render "key_requests/wizard/agreement"
      when 6
        if @key_request.update(status: :waiting_for_approval)
          redirect_to key_request_path(@key_request.id),
                      notice:
                        "You have successfully submitted the key request form, please wait a few days for an admin to review your form."
        else
          redirect_to key_request_steps_path(
                        key_request_id: @key_request.id,
                        step: 1
                      ),
                      alert:
                        "There was an error when submitting your key request form. Please make sure you fill in all the required fields."
        end
      else
        redirect_to key_request_steps_path(
                      key_request_id: @key_request.id,
                      step: 1
                    ),
                    alert: "Invalid step number"
      end
    end
  end

  private

  def key_request_params
    params.require(:key_request).permit(
      :student_number,
      :phone_number,
      :emergency_contact,
      :emergency_contact_relation,
      :emergency_contact_phone_number,
      :space_id,
      :user_status,
      :supervisor_id,
      :read_lab_rules,
      :read_policies,
      :read_agreement,
      :status,
      :question_1,
      :question_2,
      :question_3,
      :question_4,
      :question_5,
      :question_6,
      :question_7,
      :question_8,
      :question_9,
      :question_10,
      :question_11,
      :question_12,
      :question_13,
      :question_14
    )
  end

  def check_key_request
    unless @user.key_request.nil?
      redirect_to staff_dashboard_index_path,
                  notice:
                    "You already have a key request. You can edit your current key request."
    end
  end

  def set_key_request
    id = params[:id].present? ? params[:id] : params[:key_request_id]
    @key_request = KeyRequest.find_by(id: id)

    if @key_request.nil?
      redirect_to staff_dashboard_index_path, alert: "Key was not found."
    end
  end
end
