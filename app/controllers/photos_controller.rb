# frozen_string_literal: true

class PhotosController < SessionsController
  before_action :current_user
  before_action :signed_in

  private

  def photo_params
    params.require(:photo).permit(:image)
  end
end
