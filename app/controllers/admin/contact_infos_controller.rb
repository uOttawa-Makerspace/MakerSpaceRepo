class Admin::ContactInfosController < AdminAreaController
  def index
    @contact_infos = ContactInfo.all.order(name: :asc)
  end

  def new
    @contact_info = ContactInfo.new
    @contact_info.opening_hours.build
  end

  def create
    fields = params.require(:contact_info)
    space = Space.find_by(id: fields[:space_id])
    fields[:name] = space ? space.name : fields[:space_id]
    fields[:space_id] = nil unless space
    contact_info = ContactInfo.new(contact_infos_params)
    if contact_info.save!
      redirect_to admin_contact_infos_path
      flash[:notice] = "You've successfully created a new Contact Info !"
    end
  end

  def edit
    @contact_info = ContactInfo.find(params[:id])
    @contact_info.opening_hours.build if @contact_info.opening_hours.blank?
  end

  def update
    contact_info = ContactInfo.find(params[:id])
    if contact_info.update(contact_infos_params)
      flash[:notice] = "Contact Info updated"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to admin_contact_infos_path
  end

  def destroy
    contact_info = ContactInfo.find(params[:id])
    if contact_info.destroy
      flash[:notice] = "Contact Info Deleted"
    else
      flash[:alert] = "Something went wrong"
    end
    redirect_to admin_contact_infos_path
  end

  def contact_infos_params
    params.require(:contact_info).permit(
      :name,
      :email,
      :address,
      :phone_number,
      :url,
      :show_hours,
      :space_id,
      # https://api.rubyonrails.org/classes/ActiveRecord/NestedAttributes/ClassMethods.html
      # neat stuff really
      opening_hours_attributes: %i[
        id
        target_en
        target_fr
        notes_en
        notes_fr
        closed_all_week
        sunday_opening
        sunday_closing
        sunday_closed_all_day
        monday_opening
        monday_closing
        monday_closed_all_day
        tuesday_opening
        tuesday_closing
        tuesday_closed_all_day
        wednesday_opening
        wednesday_closing
        wednesday_closed_all_day
        thursday_opening
        thursday_closing
        thursday_closed_all_day
        friday_opening
        friday_closing
        friday_closed_all_day
        saturday_opening
        saturday_closing
        saturday_closed_all_day
        _destroy
      ]
    )
  end
end
