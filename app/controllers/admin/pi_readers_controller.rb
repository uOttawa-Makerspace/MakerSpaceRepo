# frozen_string_literal: true

class Admin::PiReadersController < AdminAreaController
  def update
    if raspi = PiReader.find(params[:id])
      if raspi.update(pi_reader_params)
        flash[:notice] = 'Updated successfully'
        redirect_back(fallback_location: root_path)
      else
        flash[:notice] = 'Something went wrong'
      end
    end
  end

  private

  def pi_reader_params
    params.require(:pi_reader_params).permit(:space_id, :pi_location)
  end
end
