# frozen_string_literal: true

# Applied to the stock ActiveStorage::DirectUploadsController (see
# config/initializers/direct_uploads_authentication.rb). The stock controller
# inherits from ActiveStorage::BaseController, not ApplicationController, so none
# of the app's auth applies to it. Every direct-upload form in the app is an HTML
# form behind a login (the React app and Design Day app do not use direct upload;
# see frontend-api-inventory.md), so a signed-in user is required and the declared
# size is capped before a blob row / signed URL is issued.
#
# Note: ApplicationHelper#signed_in? also accepts a Bearer JWT, but
# ActiveStorage::BaseController's protect_from_forgery rejects a Bearer-only POST in
# production (no CSRF token), so in practice this is a session-cookie flow.
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
    raw = params.dig(:blob, :byte_size)
    return if raw.nil? # the blob validations reject a missing size

    byte_size = Integer(raw.to_s, 10)
    head :content_too_large if byte_size > MAX_BYTE_SIZE
  rescue ArgumentError, TypeError
    # ActiveRecord would still cast "5000000000.0" or " 5000000000", so do not let it through
    head :unprocessable_content
  end
end
