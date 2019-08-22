class Admin::TrainingsController < AdminAreaController

  before_action :changed_training, only: [:update, :destroy]

  layout 'admin_area'

  def new
    @new_training = Training.new
  end

  def create
    space = Space.find(params["/admin/trainings"][:space_id])
    @new_training = Training.new(training_params)
    @new_training.spaces << space
    if @new_training.save
      flash[:notice] = "Training added successfully!"
    else
      flash[:alert] = "Input is invalid"
    end
    redirect_to :back
  end

  def update
    @changed_training.update(training_params)
    if @changed_training.save
      flash[:notice] = "Training renamed successfully"
    else
      flash[:alert] = "Input is invalid"
    end
    redirect_to admin_settings_path
  end

  def destroy
    if @changed_training.destroy
      flash[:notice] = "Training removed successfully"
    end
    redirect_to :back
  end

  private

  def training_params
      params.require("/admin/trainings").permit(:name)
  end

  def changed_training
    @changed_training = Training.find(params['id'])
  end

end
