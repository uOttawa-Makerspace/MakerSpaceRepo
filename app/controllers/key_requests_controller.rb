class KeyRequestsController < SessionsController
  before_action :ensure_staff_or_teams_program
  before_action :check_key_request, only: %i[new create]
  before_action :set_key_request, only: %i[show steps update_steps]
  before_action :ensure_request_owner, only: %i[steps update_steps]
  before_action :ensure_editable, only: %i[steps update_steps]

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

    @key_certification = @key_request.display_user.key_certification
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

  WIZARD_VIEWS = {
    1 => "key_requests/wizard/personal_information",
    2 => "key_requests/wizard/lab_rules",
    3 => "key_requests/wizard/safety_questionnaire",
    4 => "key_requests/wizard/policies",
    5 => "key_requests/wizard/agreement"
  }.freeze
  BOOLEAN_STEP_FIELDS = %i[read_lab_rules read_policies read_agreement].freeze

  # GET: shows one step of the wizard. It never changes the request.
  def steps
    @step = wizard_step
    if WIZARD_VIEWS.key?(@step)
      render WIZARD_VIEWS[@step]
    elsif @step == 6
      redirect_to key_request_steps_path(key_request_id: @key_request.id, step: 5)
    else
      redirect_to_first_step "Invalid step number"
    end
  end

  # PATCH: saves the submitted fields, then shows the next step (or submits the
  # request after the last one).
  def update_steps
    @step = wizard_step
    if params[:key_request].present?
      normalize_boolean_fields
      unless @key_request.update(key_request_params)
        return redirect_to(key_request_steps_path(
                             key_request_id: @key_request.id,
                             step: @step == 1 ? 1 : (params[:step].to_i - 1)
                           ),
                           alert: "An error occured while saving the key request at step #{params[:step]}: Failed to update key request")
      end
    end

    if WIZARD_VIEWS.key?(@step)
      render WIZARD_VIEWS[@step]
    elsif @step == 6
      submit_key_request
    else
      redirect_to_first_step "Invalid step number"
    end
  end

  private

  def wizard_step
    params[:step].present? ? params[:step].to_i : 1
  end

  def normalize_boolean_fields
    BOOLEAN_STEP_FIELDS.each do |field|
      next unless params[:key_request][field].present?

      params[:key_request][field] = params[:key_request][field] == "true"
    end
  end

  def submit_key_request
    if @key_request.submit
      redirect_to key_request_path(@key_request.id),
                  notice:
                    "You have successfully submitted the key request form, please wait a few days for an admin to review your form."
    else
      redirect_to_first_step "There was an error when submitting your key request form. Please make sure you fill in all the required fields."
    end
  end

  # Once submitted, a request is changed only by an admin sending it back
  # (deny returns it to in progress).
  def ensure_editable
    return if @key_request.editable_by_owner?

    state = @key_request.status_approved? ? "approved" : "submitted and waiting for approval"
    redirect_to key_request_path(@key_request.id),
                alert: "This key request is already #{state}, so it cannot be edited. An admin must send it back before you can change it."
  end

  def redirect_to_first_step(alert)
    redirect_to key_request_steps_path(key_request_id: @key_request.id, step: 1),
                alert: alert
  end

  def ensure_request_owner
    return if @user.eql?(@key_request.user)

    redirect_to staff_dashboard_index_path,
                alert: "You don't have the permission to edit this key request."
  end

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

  def ensure_staff_or_teams_program
    @user = current_user
    unless @user.staff? || @user.admin? ||
             @user.programs.pluck(:program_type).include?(Program::TEAMS)
      redirect_to root_path
      flash[:alert] = "You cannot access this area."
    end
  end
end
