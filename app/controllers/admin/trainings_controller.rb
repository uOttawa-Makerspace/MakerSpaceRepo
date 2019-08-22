class Admin::TrainingsController < AdminAreaController

  before_action :changed_training, only: [:update, :destroy]

  layout 'admin_area'

  def index
    @trainings = Training.all.order(:name)
  end

  def new
    @new_training = Training.new
  end

  def edit
    @training = Training.find(params[:id])
    @spaces = Space.all.order(:name)
  end

  def create
    @new_training = Training.new(training_params)
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
    redirect_to admin_trainings_path
  end

  def destroy
    if @changed_training.destroy
      flash[:notice] = "Training removed successfully"
    end
    redirect_to :back
  end

  private

  def training_params
      params.require(:training).permit(:name, space_ids: [])
  end

  def changed_training
    @changed_training = Training.find(params['id'])
  end

end
