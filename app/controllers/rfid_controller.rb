class RfidController < SessionsController

  def card_number
  	rfid = Rfid.find_by(card_number: params[:card_number])

		if rfid
      if rfid.user_id
        render json: { success: "RFID exist" }, status: :ok
      else
        rfid.touch
				render json: { error: "Temporary RFID already exists" }, status: :unprocessable_entity
      end
		else
			new_rfid = Rfid.create(rfid_params)
			if new_rfid.valid?
				render json: { new_rfid: "Temporary RFID created" }, status: :unprocessable_entity
			end
		end
  end

  private

  def rfid_params
    params.permit(:card_number)
  end

end
