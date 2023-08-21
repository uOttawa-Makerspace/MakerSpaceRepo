class KeyRequestsController < StaffAreaController
  layout "staff_area"

  before_action :check_key_request, only: %i[new create]

  def new
    @key_request = KeyRequest.new
  end

  def create
    @key_request = KeyRequest.new(key_request_params.merge(user_id: @user.id))

    if @key_request.save
      redirect_to staff_dashboard_index_path,
                  notice:
                    "Successfully submitted form. Please wait a few business days for your request to be processed by an admin."
    else
      flash[:alert] = "Something went wrong while trying to submit the form."
      render :new
    end
  end

  def show
    @key_request = KeyRequest.find_by(id: params[:id])

    if @key_request.nil?
      redirect_to staff_dashboard_index_path, alert: "Key was not found."
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
      :supervisor_id,
      :read_lab_rules,
      :read_policies,
      :read_agreement
    )
  end

  def check_key_request
    unless @user.key_request.nil?
      redirect_to staff_dashboard_index_path,
                  notice:
                    "You already have a key request. You can edit your current key request."
    end
  end
end
