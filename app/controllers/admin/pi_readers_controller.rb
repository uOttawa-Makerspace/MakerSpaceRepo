# frozen_string_literal: true

class Admin::PiReadersController < AdminAreaController
  # Readers no longer register themselves on their first tap (D-EQ03); an admin
  # registers the reader's MAC address here.
  def create
    attrs = pi_reader_create_params
    legacy = PiReader.find_by_mac(attrs[:pi_mac_address])
    if legacy && legacy.space_id.nil?
      # A legacy self-registered row for this MAC exists: adopt it instead of failing,
      # but only into a space that exists (a space-less reader cannot tap).
      space = Space.find_by(id: attrs[:space_id].to_s) if attrs[:space_id].present?
      if space.nil?
        flash[:alert] = "Space must exist"
      elsif legacy.update(
        pi_mac_address: PiReader.normalize_mac(attrs[:pi_mac_address]),
        space_id: space.id,
        pi_location: attrs[:pi_location].presence || legacy.pi_location
      )
        flash[:notice] = "Reader registered"
      else
        flash[:alert] = legacy.errors.full_messages.to_sentence
      end
      return redirect_back(fallback_location: root_path)
    end

    reader = PiReader.new(attrs)
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
