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
        rfid.update(params)
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
    active_sessions = rfid.user.lab_sessions.where("sign_out_time > ?", Time.now)
    new_location = PiReader.find_by(pi_mac_address: params[:mac_address])
    if active_sessions.present?
      active_sessions.update_all(sign_out_time: Time.now)
      last_active_location = PiReader.find_by(space_id: active_sessions.last.space.id)
      if last_active_location != new_location
        new_session(rfid, new_location)
      end
    else
      new_session(rfid, new_location)
    end
  end

  def new_session (rfid, new_location)
    sign_in = Time.now
    sign_out = sign_in + 3.hours
    new_session = rfid.user.lab_sessions.new(sign_in_time: sign_in, sign_out_time: sign_out, mac_address: params[:mac_address], space_id: new_location.space.id)
    new_session.save
  end
end
