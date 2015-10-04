class RfidController < SessionsController

  before_action :current_user, only: [:new, :admin?, :new_card_number]
  before_action :admin?, only: :new

  def new
  	@rfid = Rfid.new
	end

	def create
		user = User.find_by! username: params[:username]
		temp_rfid = Rfid.find_by card_number: params[:rfid][:card_number]
		temp_rfid.destroy if user.present? && temp_rfid.present?
		rfid = user.build_rfid(card_number: params[:rfid][:card_number])

    respond_to do |format|
			if rfid.save
				flash[:notice] = "Card number was saved to users account successfully!"
				format.html { redirect_to new_rfid_path }
				format.json { render json: { success: "Dude, did you just hack into my server?!" }, status: :ok }
			else
				flash[:alert] = rfid.errors.messages	
				format.html { redirect_to new_rfid_path }
				render json: { error: rfid.errors.messages }, status: :unprocessable_entity
			end
		end

    rescue
			flash[:alert] = "Username doesn't exist."	
	    respond_to do |format|
				format.html { redirect_to new_rfid_path }
				format.json { render json: { error: "Username doesn't exist." }, status: :unprocessable_entity }
			end
	end

	def destroy
		@user = User.find_by username: params[:username]
		@user.rfid.destroy
		render json: { success: "Successfully deleted RFID!" }, status: :ok

    rescue
			render json: { error: "Either your username doesn't exist or the user does not have an RFID" },
			  status: :unprocessable_entity
	end

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

  def new_card_number
  	@rfids = Rfid.where(user_id: nil).order("created_at DESC").first(25)
  end

  private

  def admin?
  	return redirect_to new_user_path unless @user.role.eql?("admin")
  end
end