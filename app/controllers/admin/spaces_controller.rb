# frozen_string_literal: true

class Admin::SpacesController < AdminAreaController
  layout 'admin_area'

  def index; end

  #def new
  #  @space = Space.new
  #end

  def create
    space = Space.new(space_params)
    if space.save
      flash[:notice] = 'Space created successfully!'
    else
      flash[:alert] = 'Something went wrong.'
    end
    redirect_back(fallback_location: root_path)
  end

  def edit
    @new_training = Training.new
    unless @space = Space.find(params[:id])
      flash[:alert] = 'Not Found'
      redirect_back(fallback_location: root_path)
    end
  end

  def destroy
    space = Space.find(params[:id])
    if params[:admin_input] == space.name.upcase
      raspis = PiReader.where(space_id: space.id)
      raspis.update_all(space_id: nil)
      flash[:notice] = 'Space deleted!' if space.destroy
    else
      flash[:alert] = 'Invalid Input'
    end
    redirect_to admin_spaces_path
  end

  private

  def space_params
    params.require(:space_params).permit(:name)
  end
end
