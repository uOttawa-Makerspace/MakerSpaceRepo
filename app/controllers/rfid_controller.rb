class RfidController < SessionsController

  def card_number
  	rfid = Rfid.find_by card_number: params[:rfid]

		if rfid && rfid.user_id
			render json: { success: "RFID exist" }, status: :ok
		else
			new_rfid = Rfid.create(card_number: params[:rfid])
			if new_rfid.valid?
				render json: { new_rfid: "Temporary RFID created" }, status: :unprocessable_entity
			else
				render json: { error: "Temporary RFID already exists" }, status: :unprocessable_entity
			end
		end
  end

end
