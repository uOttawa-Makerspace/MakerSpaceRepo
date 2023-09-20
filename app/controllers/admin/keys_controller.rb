class Admin::KeysController < AdminAreaController
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
    @keys = Key.order(created_at: :desc)
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

  def assign_key
    user = KeyRequest.find(params[:key][:key_request_id]).user

    key_transaction =
      KeyTransaction.new(
        user_id: user.id,
        key_id: @key.id,
        deposit_amount: params[:deposit_amount]
      )
    if @key.status_inventory? &&
         @key.update(key_params.merge(user_id: user.id, status: :held)) &&
         key_transaction.save
      redirect_to admin_keys_path, notice: "Successfully assigned key"
    else
      redirect_to admin_keys_path,
                  alert: "Something went wrong while trying to assign the key"
    end
  end

  def revoke_key
    if @key.status_held? &&
         @key.update(user_id: nil, key_request_id: nil, status: :inventory) &&
         @key.get_latest_key_transaction.update(
           return_date: Date.today,
           deposit_return_date: params[:deposit_return_date]
         )
      redirect_to admin_keys_path, notice: "Successfully revoked key"
    else
      redirect_to admin_keys_path,
                  alert: "Something went wrong while trying to revoke the key"
    end
  end

  def requests
    @key_requests = KeyRequest.order(created_at: :asc)
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
      :supervisor_id,
      :key_request_id,
      :status,
      :key_type,
      :custom_keycode
    )
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
