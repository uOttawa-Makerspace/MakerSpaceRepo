class Admin::ContactInfosController < AdminAreaController

  def index
    @contact_infos = ContactInfo.all.order(name: :asc)
  end

  def new
    @contact_info = ContactInfo.new
    @contact_info.build_opening_hour
  end

  def create
    contact_info = ContactInfo.new(contact_infos_params)
    if contact_info.save!
      redirect_to admin_contact_infos_path
      flash[:notice] = "You've successfully created a new Contact Info !"
    end
  end

  def edit
    @contact_info = ContactInfo.find(params[:id])
    @contact_info.build_opening_hour if @contact_info.opening_hour.blank?
  end

  def update
    contact_info = ContactInfo.find(params[:id])
    if contact_info.update(contact_infos_params)
      flash[:notice] = 'Contact Info updated'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_to admin_contact_infos_path
  end

  def destroy
    contact_info = ContactInfo.find(params[:id])
    if contact_info.destroy
      flash[:notice] = 'Contact Info Deleted'
    else
      flash[:alert] = 'Something went wrong'
    end
    redirect_to admin_contact_infos_path
  end

  def contact_infos_params
    params.require(:contact_info).permit(:name, :email, :address, :phone_number, :url, :show_hours, opening_hour_attributes: [:students, :public, :summer])
  end

end
