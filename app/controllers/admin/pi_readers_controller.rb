# frozen_string_literal: true

class Admin::PiReadersController < AdminAreaController
  # Readers no longer register themselves on their first tap (D-EQ03); an admin
  # registers the reader's MAC address here.
  def create
    reader = PiReader.new(pi_reader_create_params)
    if reader.save
      flash[:notice] = "Reader registered"
    else
      flash[:alert] = reader.errors.full_messages.to_sentence
    end
    redirect_back(fallback_location: root_path)
  end

  def update
    if raspi = PiReader.find(params[:id])
      if raspi.update(pi_reader_params)
        flash[:notice] = "Updated successfully"
        redirect_back(fallback_location: root_path)
      else
        flash[:notice] = "Something went wrong"
      end
    end
  end

  private

  def pi_reader_create_params
    params.require(:pi_reader_params).permit(:pi_mac_address, :space_id, :pi_location)
  end

  def pi_reader_params
    params.require(:pi_reader_params).permit(:space_id, :pi_location)
  end
end
