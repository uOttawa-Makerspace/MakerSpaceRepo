class Admin::KeysController < AdminAreaController
  before_action :set_key, only: %i[show edit destroy update]
  before_action :set_key_request, only: %i[approve_key_request deny_key_request]

  def index
    @keys = Key.order(created_at: :desc)
    @spaces = Space.order(name: :asc)
  end

  def show
  end

  def create
    create_params =
      (params[:key][:status] == "inventory") ? key_inventory_params : key_params
    @key = Key.new(create_params)

    if @key.save
      flash[:notice] = "Successfully created key."
      redirect_to admin_keys_path
    else
      flash[:alert] = "Something went wrong while creating the key."
      render :new
    end
  end

  def new
    @key = Key.new
    @key_requests =
      KeyRequest
        .where(status: :approved)
        .joins(:user)
        .pluck("users.username", "key_requests.id")
  end

  def edit
    @key_requests =
      KeyRequest
        .where(status: :approved)
        .joins(:user)
        .pluck("users.username", "key_requests.id")
  end

  def update
    update_params =
      (params[:key][:status] == "inventory") ? key_inventory_params : key_params

    if @key.update(update_params)
      flash[:notice] = "The key was successfully updated."
      redirect_to admin_keys_path
    else
      flash[:alert] = "Something went wrong while updating the key."
      render :edit
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
                  alert: "Something went wrong while approving key request."
    end
  end

  def deny_key_request
    if @key_request.status_waiting_for_approval? &&
         @key_request.update(status: :in_progress)
      redirect_to requests_admin_keys_path,
                  notice: "Successfully denied key request."
    else
      redirect_to requests_admin_keys_path,
                  alert: "Something went wrong while approving key request."
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
      :keycode
    )
  end

  def key_inventory_params
    params.require(:key).permit(
      :number,
      :space_id,
      :status,
      :key_type,
      :keycode,
      :supervisor_id
    )
  end

  def set_key
    @key = Key.find_by(id: params[:id])

    redirect_to admin_keys_path, alert: "The key id was not found." if @key.nil?
  end

  def set_key_request
    @key_request = KeyRequest.find_by(id: params[:id])

    if @key_request.nil?
      redirect_to admin_keys_path, alert: "The key request id was not found."
    end
  end
end
