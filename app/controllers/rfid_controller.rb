class RfidController < SessionsController

  def card_number
    rfid = Rfid.find_by(card_number: params[:rfid])

    if rfid
      if rfid.user_id
        render json: { success: "RFID exist" }, status: :ok
      else
        rfid.touch
        render json: { error: "Temporary RFID already exists" }, status: :unprocessable_entity
      end
    else
      new_rfid = Rfid.create(card_number: params[:rfid])
      if new_rfid.valid?
        render json: { new_rfid: "Temporary RFID created" }, status: :unprocessable_entity
      else
        render json: { new_rfid: "Error, requires rfid param"}, status: :unprocessable_entity
      end
    end
  end
end
