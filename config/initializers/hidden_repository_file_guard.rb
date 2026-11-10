# frozen_string_literal: true

# Files of a hidden (deleted) repository are not served: the guard is added to every stock Active
# Storage controller that serves a file. Added in to_prepare from a plain required module in lib/,
# for the same reason as the direct upload filter (see direct_uploads_authentication.rb).
require Rails.root.join("lib/hidden_repository_file_guard")

Rails.application.config.to_prepare do
  [
    ActiveStorage::Blobs::RedirectController,
    ActiveStorage::Blobs::ProxyController,
    ActiveStorage::Representations::RedirectController,
    ActiveStorage::Representations::ProxyController,
    ActiveStorage::DiskController
  ].each { |controller| controller.include HiddenRepositoryFileGuard }
end
