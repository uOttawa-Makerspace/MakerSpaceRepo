class Admin::TrainingsController < AdminAreaController
  layout 'admin_area'

  def add_training
    if params[:training_name].present? && !Training.find_by(name: params[:training_name]).present?
      Training.create(name: params[:training_name])
      flash[:notice] = "Training added successfully!"
    else
      flash[:alert] = "Training already exists or input is invalid"
    end
    redirect_to admin_settings_path
  end

  def rename_training
    if !params[:training_name].present? || params[:training_name]==""
      flash[:alert] = "Please enter an existing training name"
    elsif !params[:training_new_name].present?
      flash[:alert] = "Please enter new name for the training"
    elsif !Training.find_by(name: params[:training_name]).present?
      flash[:alert] = "Please enter an existing training in order to rename it!"
    elsif Training.find_by(name: params[:training_new_name]).present?
      flash[:alert] = "There already exists a training with this name!"
    else
      @training = Training.find_by(name: params[:training_name])
      @training.name = params[:training_new_name]
      @training.save
      flash[:notice] = "Training renamed successfully"
    end
    redirect_to admin_settings_path
  end

  def remove_training
    if !params[:training_name].present? || params[:training_name]==""
      flash[:alert] = "Please enter an existing training name"
    elsif !Training.find_by(name: params[:training_name]).present?
      flash[:alert] = "Please enter an existing training in order to remove it!"
    else
      Training.find_by(name: params[:training_name]).destroy
      flash[:notice] = "Training removed successfully"
    end
    redirect_to admin_settings_path
  end

end
