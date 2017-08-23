class RfidController < SessionsController

  def card_number

    if !(PiReader.find_by(pi_mac_address: params[:mac_address]))
      new_reader = PiReader.new(pi_mac_address: params[:mac_address])
      new_reader.save
    end

    rfid = Rfid.find_by(card_number: params[:rfid])

    if rfid
      if rfid.user_id
        render json: { success: "RFID exist" }, status: :ok
        check_session(rfid)
      else
        rfid.touch
        render json: { error: "Temporary RFID already exists" }, status: :unprocessable_entity
      end
    else
      new_rfid = Rfid.create(card_number: params[:rfid], mac_address: params[:mac_address])
      if new_rfid.valid?
        render json: { new_rfid: "Temporary RFID created" }, status: :unprocessable_entity
      else
        render json: { new_rfid: "Error, requires rfid param"}, status: :unprocessable_entity
      end
    end
  end

  def check_session(rfid)
    active_session = rfid.user.lab_sessions.where("sign_out_time > ?", Time.now)
    if active_session.present?
      active_session.update_all(sign_out_time: Time.now)
      active_location = PiReader.find_by(pi_mac_address: active_session.first.try(:mac_address)).try(:pi_location)
      new_location = PiReader.find_by(pi_mac_address: params[:mac_address]).try(:pi_location)
      if active_location != new_location
        new_session(rfid)
      end
    else
      new_session(rfid)
    end
  end

  def new_session (rfid)
    sign_in = Time.now
    sign_out = sign_in + 3.hours
    raspi = PiReader.find_by(pi_mac_address: params[:mac_address]).try(params[:pi_location])
    new_session = rfid.user.lab_sessions.new(sign_in_time: sign_in, sign_out_time: sign_out, mac_address: params[:mac_address], pi_reader_id: raspi.id)
    new_session.save
  end
end
