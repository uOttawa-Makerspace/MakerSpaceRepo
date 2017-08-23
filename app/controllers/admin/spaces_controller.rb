class Admin::SpacesController < AdminAreaController

  layout 'admin_area'

  def index
  end

  def new
    @space = Space.new
  end

  def create
    space = Space.new(space_params)
    if space.save
      flash[:notice] = "Space created successfully!"
    else
      flash[:alert] = "Something went wrong."
    end
    redirect_to :back
  end

  def edit
    unless @space = Space.find_by(space_params)
      @space = Space.first
    end
  end

  def destroy
    if Space.find_by(space_params).destroy
      flash[:notice] = "Space deleted successfully!"
    else
      flash[:alert] = "Name is required"
    end
    redirect_to admin_spaces_path
  end


  private

  def space_params
    params.require(:space_params).permit(:name)
  end

end
