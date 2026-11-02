# frozen_string_literal: true

# Direct uploads require a signed-in user: the authentication filter is added to the stock
# ActiveStorage::DirectUploadsController.
# Extending it in to_prepare (rather than re-routing to a subclass) keeps the
# engine route and the `rails_direct_uploads_path` helper, and leaves no second
# route behind.
#
# The module lives in lib/ and is required explicitly, NOT in app/: an app/ module
# is reloadable, so every dev reload would create a new module object and include
# it again into the (non-reloaded) engine controller, stacking duplicate callbacks.
# A plain required module is the same object across reloads, so `include` is a no-op
# after the first time.
require Rails.root.join("lib/direct_upload_authentication")

Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.include DirectUploadAuthentication
end
