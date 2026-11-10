# frozen_string_literal: true

# Added to ActiveStorage::Blob (config/initializers/hidden_repository_file_guard.rb).
module HiddenRepositoryBlob
  # True when the stored file belongs only to hidden repositories (as a photo, a repo file or
  # directly): it must not be served. A file that is also attached to something visible is served.
  def hidden_by_repository?
    all_attachments = ActiveStorage::Attachment.where(blob_id: id)
    hidden_attachments = all_attachments.where(id: hidden_repository_attachment_ids)
    hidden_attachments.exists? && !all_attachments.where.not(id: hidden_attachments.select(:id)).exists?
  end

  private

  def hidden_repository_attachment_ids
    hidden_ids = Repository.hidden.reorder(nil).select(:id)
    attachments = ActiveStorage::Attachment
    direct = attachments.where(record_type: "Repository", record_id: hidden_ids)
    photos = attachments.where(record_type: "Photo", record_id: Photo.where(repository_id: hidden_ids).select(:id))
    files = attachments.where(record_type: "RepoFile", record_id: RepoFile.where(repository_id: hidden_ids).select(:id))
    direct.or(photos).or(files).select(:id)
  end
end
