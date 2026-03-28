class MovePhotosToProjectProposal < ActiveRecord::Migration[7.2]
  # Don't imagine you'd want to revert this migration.
  def up
    Photo
      .where.not(project_proposal_id: nil)
      .each do |photo|
        next unless photo.image.attached?

        ProjectProposal
          .find(photo.project_proposal_id)
          .photos
          .attach(photo.image.blob)
      end

    RepoFile
      .where.not(project_proposal_id: nil)
      .each do |repo_file|
        next unless repo_file.file.attached?

        ProjectProposal
          .find(repo_file.project_proposal_id)
          .project_files
          .attach(repo_file.file.blob)
      end

    Photo.where.not(project_proposal_id: nil).destroy_all
    RepoFile.where.not(project_proposal_id: nil).destroy_all
  end
end
