class KeyRequestsController < StaffAreaController
  layout "staff_area"

  def new
    @key_request = KeyRequest.new
  end

  def create
    @key_request = KeyRequest.new(key_request_params.merge(user_id: @user.id))

    if @key_request.save
      flash[
        :notice
      ] = "Successfully submitted form. Please wait a few business days for your request to be processed by an admin."
      redirect_to staff_dashboard_index_path
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
end