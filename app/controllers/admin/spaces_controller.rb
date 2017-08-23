class Admin::SpacesController < AdminAreaController

  layout 'admin_area'

  def index
    @space = Space.first
  end

  def new
    @space = Space.new
  end

  def create
    if name = params[:name]
      @space = Space.new(name: name)
    else
      flash[:alert] = "Name is required"
    end
    if @space.save
      flash[:notice] = "Training added successfully!"
    else
      flash[:alert] = "Something went wrong."
    end
    redirect_to admin_spaces_path
  end

  def edit
    unless @space = Space.find_by(space_params)
      @space = Space.first
    end
  end

  def destroy
    if name = params[:name]
      if Space.find_by(name: param).destroy
        flash[:notice] = "Training removed successfully"
      end
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
