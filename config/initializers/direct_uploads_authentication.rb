# frozen_string_literal: true

# D-C46: the stock ActiveStorage::DirectUploadsController is unauthenticated.
# Extending it in to_prepare (rather than re-routing to a subclass) keeps the
# engine route and the `rails_direct_uploads_path` helper the JS client uses,
# and leaves no second unauthenticated route behind.
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.include DirectUploadAuthentication
end
