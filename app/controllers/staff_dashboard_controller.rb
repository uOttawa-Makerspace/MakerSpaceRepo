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
      if pi = Space.find_by(name: @user.location)&.pi_readers.first
        new_mac = pi.pi_mac_address
        rfid.mac_address = new_mac
      end
      rfid.save
    end
    redirect_to :back
  end

end
