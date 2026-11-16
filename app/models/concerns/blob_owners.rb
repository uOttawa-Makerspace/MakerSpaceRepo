# frozen_string_literal: true

# Added to ActiveStorage::Blob (config/initializers/stock_file_guard.rb).
module BlobOwners
  # The [record_type, record_id] of every attachment of the stored file, in one query.
  def attachment_owners
    ActiveStorage::Attachment.where(blob_id: id).pluck(:record_type, :record_id)
  end
end
