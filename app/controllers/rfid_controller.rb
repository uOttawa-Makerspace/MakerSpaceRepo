class RfidController < SessionsController

	def create
		@user = User.find_by username: params[:username]
		rfid = @user.build_rfid(card_number: params[:rfid])
		if rfid.save
			render json: { success: "Dude, did you just hack into my server?!" }, status: :ok
		else
			render json: { error: rfid.errors.messages }, status: :unprocessable_entity
		end

    rescue
			render json: { error: "Username doesn't exist." }, status: :unprocessable_entity
	end

	def destroy
		@user = User.find_by username: params[:username]
		@user.rfid.destroy
		render json: { success: "Successfully deleted RFID" }, status: :ok

    rescue
			render json: { error: "Either your username doesn't exist or the user does not have an RFID" },
			  status: :unprocessable_entity
	end

  def card_number
  	rfid = Rfid.find_by card_number: params[:rfid]

		if rfid
			render json: { success: "RFID exist" }, status: :ok
		else
			render json: { error: "RFID does not exist" }, status: :unprocessable_entity
		end
  end

end