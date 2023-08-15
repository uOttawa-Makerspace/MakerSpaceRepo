class KeyRequestsController < StaffAreaController
  layout "staff_area"

  def new
    @key_request = KeyRequest.new
  end

  def create
    @key_request =
      KeyRequest.new(
        key_request_params.merge(
          status: :waiting_for_approval,
          user_id: @user.id
        )
      )
    update_files

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
      :supervisor_id
    )
  end

  def update_files
    if params[:delete_files].present?
      file_ids = params[:delete_files].split(",")

      @key_request.files.each { |f| f.purge if file_ids.include?(f.id.to_s) }
    end

    if params[:key_request][:files].present?
      params[:key_request][:files].each { |f| @key_request.files.attach(f) }
    end
  end
end
