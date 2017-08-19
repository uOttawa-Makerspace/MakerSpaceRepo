class Admin::SpacesController < ApplicationController

  layout 'admin_area'

  def new
    @new_space = Space.new
  end

  def create
    if name = params['name']
      @new_space = Space.new(name: name)
      if @new_training.save
        flash[:notice] = "space created successfully!"
      else
        flash[:alert] = "Something Went Wrong"
      end
    else
      flash[:alert] = "Invalid Input"
    end
    redirect_to :back
  end

  def update
    if name = params['name']
      @space.update(name: name)
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
    redirect_to admin_settings_path
  end


end
