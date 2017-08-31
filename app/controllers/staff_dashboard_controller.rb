class StaffDashboardController < StaffAreaController

  def index
  end

  def link_rfid
    binding.pry
    if params['user_id'].present? && params['card_number'].present?
      rfid = Rfid.find_by(card_number: params['card_number'])
      rfid.user_id = params['user_id']
      rfid.save
    end
    redirect_to :back
  end

end
