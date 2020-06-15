# frozen_string_literal: true

class Admin::TrainingsController < AdminAreaController
  before_action :changed_training, only: %i[update destroy]

  layout 'admin_area'

  def index
    @trainings = Training.all.order(:name)
  end

  def new
    @new_training = Training.new
    @spaces = Space.all.order(:name)
  end

  def edit
    @training = Training.find(params[:id])
    @spaces = Space.all.order(:name)
  end

  def create
    @new_training = Training.new(training_params)
    if @new_training.save
      flash[:notice] = 'Training added successfully!'
    else
      flash[:alert] = 'Input is invalid'
    end
    redirect_to admin_trainings_path
  end

  def update
    @changed_training.update(training_params)
    if @changed_training.save
      flash[:notice] = 'Training renamed successfully'
    else
      flash[:alert] = 'Input is invalid'
    end
    redirect_to admin_trainings_path
  end

  def destroy
    flash[:notice] = 'Training removed successfully' if @changed_training.destroy
    redirect_to admin_trainings_path
  end

  private

  def training_params
    params.require(:training).permit(:name, space_ids: [])
  end

  def changed_training
    @changed_training = Training.find(params['id'])
  end
end
