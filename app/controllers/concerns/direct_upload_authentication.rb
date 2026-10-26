# frozen_string_literal: true

# Applied to the stock ActiveStorage::DirectUploadsController (see
# config/initializers/direct_uploads_authentication.rb). The stock controller
# inherits from ActiveStorage::BaseController, not ApplicationController, so none
# of the app's auth applies to it. Every direct-upload form in the app lives
# behind a login, so a signed-in user (session or JWT) is required, and the
# declared size is capped before a blob row / signed URL is issued.
module DirectUploadAuthentication
  extend ActiveSupport::Concern

  MAX_BYTE_SIZE = 1.gigabyte

  included do
    include ApplicationHelper
    before_action :require_signed_in_user
    before_action :limit_byte_size
  end

  private

  def require_signed_in_user
    head :unauthorized unless signed_in?
  end

  def limit_byte_size
    byte_size = params.dig(:blob, :byte_size).to_s
    return unless byte_size.match?(/\A\d+\z/) && byte_size.to_i > MAX_BYTE_SIZE

    head :content_too_large
  end
end
