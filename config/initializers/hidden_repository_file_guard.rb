# frozen_string_literal: true

# Files of a hidden (deleted) repository are not served: the guard is added to every stock Active
# Storage controller that serves a file, and the blob check is added to ActiveStorage::Blob. Done in
# to_prepare, because the engine classes are not reloaded but the app's modules are.
Rails.application.config.to_prepare do
  ActiveStorage::Blob.include HiddenRepositoryBlob
  [
    ActiveStorage::Blobs::RedirectController,
    ActiveStorage::Blobs::ProxyController,
    ActiveStorage::Representations::RedirectController,
    ActiveStorage::Representations::ProxyController,
    ActiveStorage::DiskController
  ].each { |controller| controller.include HiddenRepositoryFileGuard }
end
