class Admin::KeysController < AdminAreaController
  before_action :set_key,
                only: %i[show edit destroy update assign revoke assign_key revoke_key history]
  before_action :set_key_request, only: %i[approve_key_request deny_key_request]

  def index
    @keys = Key.includes(:space, :holder, :supervisor).order(updated_at: :desc)
    @spaces = Space.order(name: :asc)
  end

  def show
  end

  def create
    @key = Key.new(key_params)

    if @key.save
      flash[:notice] = "Successfully created key."
      redirect_to admin_keys_path
    else
      flash[:alert] = "Something went wrong while creating the key."
      redirect_to new_admin_key_path
    end
  end

  def new
    @key = Key.new
    @space_select = Space.order(name: :asc).map { |s| ["#{s.name} (#{s.keycode})", s.id] }
  end

  def edit
    @space_select = Space.order(name: :asc).map { |s| ["#{s.name} (#{s.keycode})", s.id] }
  end

  def update
    update_params = @key.status_held? ? key_params.except(:status) : key_params

    if @key.update(update_params)
      flash[:notice] = "The key was successfully updated."
      redirect_to admin_keys_path
    else
      flash[:alert] = "Something went wrong while updating the key."
      redirect_to edit_admin_key_path
    end
  end

  def destroy
    if @key.destroy
      flash[:notice] = "Successfully deleted key."
    else
      flash[:alert] = "Something went wrong while trying to delete the key."
    end
    redirect_to admin_keys_path
  end

  def assign
    @admin_options = User.where(role: "admin").order("LOWER(name) ASC").pluck(:name, :id)

    @staff_options =
      User
        .staff_or_teams_program
        .includes(:key_request)
        .to_a
        .sort_by { |user| user.name.to_s.downcase }
        .map do |user|
          label = if user.key_request.blank?
                    " (No request form)"
                  elsif user.key_request.status_approved?
                    " (Approved)"
                  elsif user.key_request.status_waiting_for_approval?
                    " (Request form awaiting approval)"
                  elsif user.key_request.status_in_progress?
                    " (In progress)"
                  else
                    " (#{user.key_request.status.humanize})"
                  end
          ["#{user.name}#{label}", user.id]
        end
  end

  def assign_key
    unless @key.status_inventory?
      return redirect_to admin_keys_path, alert: "Something went wrong while trying to assign the key"
    end

    holder = resolve_holder
    if holder.nil?
      message = @holder_errors&.any? ? @holder_errors.join(', ') : "Please select a user or provide complete external contact details."
      return redirect_to admin_keys_path, alert: message
    end

    ActiveRecord::Base.transaction do
      @key.update!(key_params.except(:user_id).merge(holder: holder, status: :held))
      KeyTransaction.create!(holder: holder, key_id: @key.id, deposit_amount: params[:deposit_amount])
    end

    redirect_to admin_keys_path, notice: "Successfully assigned key"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_keys_path, alert: "Something went wrong: #{e.record.errors.full_messages.join(', ')}"
  end

  def revoke_key
    latest_transaction = @key.get_latest_key_transaction
    if @key.status_held? && latest_transaction.present? &&
         @key.update(holder: nil, status: :inventory) &&
         latest_transaction.update(
           return_date: Time.zone.today,
           deposit_return_date:
             params[:deposit_return_date].presence&.to_date ||
               (Time.zone.today if latest_transaction.deposit_amount.to_f.zero?)
         )
      redirect_to admin_keys_path, notice: "Successfully revoked key"
    else
      redirect_to admin_keys_path, alert: "Something went wrong while trying to revoke the key"
    end
  end

  def requests
    @key_requests = KeyRequest.order(created_at: :asc)
  end

  def approve_key_request
    if @key_request.status_waiting_for_approval? && @key_request.update(status: :approved)
      redirect_to requests_admin_keys_path, notice: "Successfully approved key request."
    else
      redirect_to requests_admin_keys_path, alert: "Something went wrong while approving the key request."
    end
  end

  def deny_key_request
    if @key_request.status_waiting_for_approval? && @key_request.update(status: :in_progress)
      redirect_to requests_admin_keys_path, notice: "Successfully denied key request."
    else
      redirect_to requests_admin_keys_path, alert: "Something went wrong while denying the key request."
    end
  end

  def history
  end

  private

  def resolve_holder
    if params[:assignment_type] == 'external'
      ext_params = params[:external_contact]
      return nil unless ext_params.respond_to?(:permit) || ext_params.is_a?(Hash)

      ext = ext_params.is_a?(ActionController::Parameters) ? ext_params.permit(:first_name, :last_name, :email, :phone) : ActionController::Parameters.new(ext_params).permit(:first_name, :last_name, :email, :phone)
      return nil if ext[:email].blank? || ext[:first_name].blank? || ext[:last_name].blank?

      contact = ExternalContact.find_or_create_by_details(**ext.to_h.symbolize_keys)
      return contact if contact&.persisted?

      @holder_errors = contact&.errors&.full_messages
      nil
    else
      User.find_by(id: params.dig(:key, :user_id).presence || params[:user_id].presence)
    end
  end

  def key_params
    params.require(:key).permit(
      :number,
      :space_id,
      :user_id,
      :supervisor_id,
      :status,
      :key_type,
      :custom_keycode,
      :additional_info
    )
  end

  def set_key
    key_id = params[:id].presence || params[:key_id].presence
    @key = Key.find_by(id: key_id)

    redirect_to admin_keys_path, alert: "The key id was not found." if @key.nil?
  end

  def set_key_request
    @key_request = KeyRequest.find_by(id: params[:id].presence || params[:key_request_id].presence)

    if @key_request.nil?
      redirect_to admin_keys_path, alert: "The key request id was not found."
    end
  end
end