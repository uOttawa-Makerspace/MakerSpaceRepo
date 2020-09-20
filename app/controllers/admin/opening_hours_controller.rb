class Admin::OpeningHoursController < AdminAreaController

  def index
    @hours = OpeningHour.all
  end

  def new
    @hour = OpeningHour.new
  end

  def create
    hour = OpeningHour.new(opening_hours_params)
    if hour.save!
      redirect_to admin_opening_hours_path
      flash[:notice] = "You've successfully created a new Opening Hour !"
    end
  end

  def edit
    @hour = OpeningHour.find(params[:id])
  end

  def update
    hour = OpeningHour.find(params[:id])
    if hour.update(opening_hours_params)
      flash[:notice] = 'Opening Hour updated'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_to admin_opening_hours_path
  end

  def destroy
    hour = OpeningHour.find(params[:id])
    if hour.destroy
      flash[:notice] = 'Opening Hour Deleted'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_to admin_opening_hours_path
  end

  def opening_hours_params
    params.require(:opening_hour).permit(:name, :email, :address, :phone_number, :url)
  end

end
