class Admin::KeysController < AdminAreaController
  before_action :set_key, only: %i[edit destroy update]

  def index
    @keys = Key.all.order(created_at: :desc)
  end

  def create
    @key = Key.new(key_params)

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
    if @key.update(key_params)
      flash[:notice] = "The key was successfully updated."
      redirect_to admin_keys_path
    else
      flash[:alert] = "Something went wrong while updating the key."
      render :edit
    end
  end

  def destroy
    if @key.delete
      flash[:notice] = "Successfully deleted key."
    else
      flash[:alert] = "Something went wrong while trying to delete the key."
    end
    redirect_to admin_keys_path
  end

  private

  def key_params
    params.require(:key).permit(
      :number,
      :user_id,
      :space_id,
      :supervisor_id,
      :status
    )
  end

  def set_key
    @key = Key.find(params[:id])
  end
end
