class KeysController < StaffAreaController
  layout "staff_area"

  def key_form
    @key = Key.new
  end

  def create
    @key =
      Key.new(
        key_params.merge(status: :waiting_for_approval, user_id: @user.id)
      )
    update_files

    if @key.save
      flash[:notice] = "Successfully submitted form."
      redirect_to staff_dashboard_index_path
    else
      flash[:alert] = "Something went wrong while trying to submit the form."
      render :key_form
    end
  end

  private

  def key_params
    params.require(:key).permit(
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

      @key.files.each { |f| f.purge if file_ids.include?(f.id.to_s) }
    end

    if params[:key][:files].present?
      params[:key][:files].each { |f| @key.files.attach(f) }
    end
  end
end
