class StaffDashboardController < StaffAreaController

  def index
  end

  def link_rfid
    if params['user_id'].present? && params['card_number'].present?
      rfid = Rfid.find_by(card_number: params['card_number'])
      rfid.user_id = params['user_id']
      rfid.save
    end
    redirect_to :back
  end

  def unlink_rfid
    if params['card_number'].present?
      rfid = Rfid.find_by(card_number: params['card_number'])
      rfid.user_id = nil
      rfid.mac_address = Space.find_by(name: @user.location).pi_readers.first.pi_mac_address rescue rfid.mac_address
      rfid.save
    end
    redirect_to :back
  end

end
