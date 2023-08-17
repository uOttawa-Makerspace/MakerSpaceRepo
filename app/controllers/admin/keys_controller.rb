class Admin::KeysController < AdminAreaController
  before_action :set_key, only: %i[show edit destroy update revoke_key]
  before_action :set_key_request, only: %i[approve approve_key deny_key]

  def index
    @keys = Key.order(created_at: :desc)
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

  private

  def key_params
    params.require(:key).permit(
      :number,
      :user_id,
      :space_id,
      :supervisor_id,
      :status,
      :type,
      :keycode
    )
  end

  def key_inventory_params
    params.require(:key).permit(:number, :space_id, :status, :type, :keycode)
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