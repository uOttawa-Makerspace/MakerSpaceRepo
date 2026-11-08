class Admin::KeysController < AdminAreaController
  HOLDER_NOT_APPROVED_MESSAGE = "The key holder must have an approved key request."

  before_action :set_key,
                only: %i[
                  show
                  edit
                  destroy
                  update
                  assign
                  revoke
                  assign_key
                  revoke_key
                  history
                ]
  before_action :set_key_request, only: %i[approve_key_request deny_key_request]

  def index
    @keys = Key.includes(:space, :display_user, :display_supervisor).order(updated_at: :desc)

    @spaces = Space.order(name: :asc)
  end

  def show
  end

  def create
    @key = Key.new(key_params)

    if @key.hands_out_by_edit?
      redirect_to admin_keys_path, alert: Key::HAND_OUT_REFUSAL
    elsif @key.save
      flash[:notice] = "Successfully created key."
      redirect_to admin_keys_path
    else
      flash[:alert] = "Something went wrong while creating the key."
      redirect_to new_admin_key_path
    end
  end

  def new
    @key = Key.new
    @space_select = []
    Space
      .order(name: :asc)
      .each do |space|
        @space_select << [space.name + " (" + space.keycode + ")", space.id]
      end
  end

  def edit
    @space_select = []
    Space
      .order(name: :asc)
      .each do |space|
        @space_select << [space.name + " (" + space.keycode + ")", space.id]
      end
  end

  def update
    @key.update_from_edit!(key_params)
    redirect_to admin_keys_path, notice: "The key was successfully updated."
  rescue Key::StateError => e
    redirect_to admin_keys_path, alert: e.message
  rescue ActiveRecord::RecordInvalid
    redirect_to edit_admin_key_path,
                alert: "Something went wrong while updating the key."
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
    @admin_options =
      User.where(role: "admin").order("LOWER(name) ASC").pluck(:name, :id)
    @staff_options =
      User
        .key_assignable
        .includes(:key_request)
        .order("LOWER(name) ASC")
        .map { |user| ["#{user.name} #{request_label(user.key_request)}", user.id] }
  end

  def assign_key
    user = User.find(params[:key][:user_id])

    unless holder_approved?(user)
      redirect_to admin_keys_path, alert: HOLDER_NOT_APPROVED_MESSAGE and return
    end

    @key.assign_to!(user, key_params, params[:deposit_amount])
    redirect_to admin_keys_path, notice: "Successfully assigned key"
  rescue ActiveRecord::RecordInvalid, Key::StateError => e
    redirect_to admin_keys_path,
                alert: failure_message("assign the key", e)
  end

  def revoke_key
    @key.revoke!(params[:deposit_return_date]&.to_date)
    redirect_to admin_keys_path, notice: "Successfully revoked key"
  rescue ActiveRecord::RecordInvalid, Key::StateError => e
    redirect_to admin_keys_path,
                alert: failure_message("revoke the key", e)
  end

  def requests
    @key_requests = KeyRequest.includes(:space, :display_user, :display_supervisor).order(created_at: :asc)
  end

  def approve_key_request
    if @key_request.status_waiting_for_approval? &&
         @key_request.update(status: :approved)
      redirect_to requests_admin_keys_path,
                  notice: "Successfully approved key request."
    else
      redirect_to requests_admin_keys_path,
                  alert: "Something went wrong while approving the key request."
    end
  end

  def deny_key_request
    if @key_request.status_waiting_for_approval? &&
         @key_request.update(status: :in_progress)
      redirect_to requests_admin_keys_path,
                  notice: "Successfully denied key request."
    else
      redirect_to requests_admin_keys_path,
                  alert: "Something went wrong while denying the key request."
    end
  end

  private

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

  def request_label(key_request)
    if key_request.blank?
      " (No request form)"
    elsif key_request.status_waiting_for_approval?
      " (Request form awaiting approval)"
    else
      ""
    end
  end

  def holder_approved?(user)
    user&.key_request&.status_approved? || false
  end

  def failure_message(action, error)
    detail =
      if error.is_a?(ActiveRecord::RecordInvalid)
        error.record.errors.full_messages.to_sentence
      else
        error.message
      end
    "Something went wrong while trying to #{action}: #{detail}"
  end

  def set_key
    key_id = params[:id].present? ? params[:id] : params[:key_id]
    @key = Key.find_by(id: key_id)

    redirect_to admin_keys_path, alert: "The key id was not found." if @key.nil?
  end

  def set_key_request
    @key_request = KeyRequest.find_by(id: params[:id])

    if @key_request.nil?
      redirect_to admin_keys_path, alert: "The key request id was not found."
    end
  end
end
