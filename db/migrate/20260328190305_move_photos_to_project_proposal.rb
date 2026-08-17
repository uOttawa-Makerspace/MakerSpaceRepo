class MovePhotosToProjectProposal < ActiveRecord::Migration[7.2]
  def up
    # 1. Attach photos to ProjectProposal
    Photo.where.not(project_proposal_id: nil).find_each do |photo|
      next unless photo.image.attached?

      ActiveStorage::Attachment.find_or_create_by!(
        name: 'photos',
        record_type: 'ProjectProposal',
        record_id: photo.project_proposal_id,
        blob_id: photo.image.blob_id
      )
    end

    # 2. Attach files to ProjectProposal
    RepoFile.where.not(project_proposal_id: nil).find_each do |repo_file|
      next unless repo_file.file.attached?

      ActiveStorage::Attachment.find_or_create_by!(
        name: 'project_files',
        record_type: 'ProjectProposal',
        record_id: repo_file.project_proposal_id,
        blob_id: repo_file.file.blob_id
      )
    end

    # 3. Use delete_all (NOT destroy_all) to avoid purging the actual files from storage
    Photo.where.not(project_proposal_id: nil).delete_all
    RepoFile.where.not(project_proposal_id: nil).delete_all
  end
end
