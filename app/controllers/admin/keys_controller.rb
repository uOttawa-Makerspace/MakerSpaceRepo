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
      flash[:alert] = validation_message(@key, "errors.admin.keys.not_created")
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
  rescue ActiveRecord::RecordInvalid => e
    redirect_to edit_admin_key_path, alert: validation_message(e.record, "errors.admin.keys.not_updated")
  end

  def destroy
    flash_write(@key, "keys.not_deleted", "Successfully deleted key.") { @key.destroy }
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
                alert: failure_message("not_assigned", e)
  end

  def revoke_key
    @key.revoke!(params[:deposit_return_date]&.to_date)
    redirect_to admin_keys_path, notice: "Successfully revoked key"
  rescue ActiveRecord::RecordInvalid, Key::StateError => e
    redirect_to admin_keys_path,
                alert: failure_message("not_revoked", e)
  end

  def requests
    @key_requests = KeyRequest.includes(:space, :display_user, :display_supervisor).order(created_at: :asc)
  end

  def approve_key_request
    answer_key_request(:approved, "request_not_approved", "Successfully approved key request.")
  end

  def deny_key_request
    answer_key_request(:in_progress, "request_not_denied", "Successfully denied key request.")
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

  # Only a request that is still waiting can be approved or denied.
  def answer_key_request(status, failure_key, notice)
    if @key_request.status_waiting_for_approval?
      flash_write(@key_request, "keys.#{failure_key}", notice) { @key_request.update(status: status) }
    else
      flash[:alert] = I18n.t("errors.admin.keys.request_not_waiting")
    end
    redirect_to requests_admin_keys_path
  end

  def failure_message(key, error)
    detail =
      if error.is_a?(ActiveRecord::RecordInvalid)
        error.record.errors.full_messages.to_sentence
      else
        error.message
      end
    [I18n.t("errors.admin.keys.#{key}"), detail].join(" ")
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
