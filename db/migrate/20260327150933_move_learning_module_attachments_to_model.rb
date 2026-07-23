class MoveLearningModuleAttachmentsToModel < ActiveRecord::Migration[7.2]
  # Don't imagine you'd want to revert this migration.
  def up
    # Create attachments directly to avoid loading application models
    # (which may run validations against missing columns during deploy).
    attach_blob_to_record = lambda do |record_type, record_id, name, blob|
      next unless blob && record_id

      ActiveStorage::Attachment.create!(
        name: name,
        record_type: record_type,
        record_id: record_id,
        blob_id: blob.id
      )
    end

    Photo.where.not(learning_module_id: nil).each do |photo|
      next unless photo.image.attached?

      attach_blob_to_record.call("LearningModule", photo.learning_module_id, "photos", photo.image.blob)
    end

    RepoFile.where.not(learning_module_id: nil).each do |repo_file|
      next unless repo_file.file.attached?

      attach_blob_to_record.call("LearningModule", repo_file.learning_module_id, "project_files", repo_file.file.blob)
    end

    Video.where.not(learning_module_id: nil).each do |video|
      next unless video.video.attached?

      video.video.each do |vid|
        attach_blob_to_record.call("LearningModule", video.learning_module_id, "videos", vid.blob)
      end
    end

    Photo.where.not(learning_module_id: nil).destroy_all
    RepoFile.where.not(learning_module_id: nil).destroy_all
    Video.where.not(learning_module_id: nil).destroy_all
  end
end
