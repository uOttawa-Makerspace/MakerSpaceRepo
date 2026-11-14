# frozen_string_literal: true

# The stock Active Storage controllers that serve a file refuse the files that MakerRepo serves only through its own
# routes or not at all: job order files, and the files of a hidden (deleted) repository. The guard is added to every
# stock controller that serves a file, and the blob checks are added to ActiveStorage::Blob. Done in to_prepare,
# because the engine classes are not reloaded but the app's modules are.
Rails.application.config.to_prepare do
  ActiveStorage::Blob.include BlobOwners
  ActiveStorage::Blob.include HiddenRepositoryBlob
  ActiveStorage::Blob.include JobOrderBlob
  [
    ActiveStorage::Blobs::RedirectController,
    ActiveStorage::Blobs::ProxyController,
    ActiveStorage::Representations::RedirectController,
    ActiveStorage::Representations::ProxyController,
    ActiveStorage::DiskController
  ].each { |controller| controller.include StockFileGuard }
end
