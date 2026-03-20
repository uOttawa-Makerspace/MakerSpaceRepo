class MoveLearningModuleAttachmentsToModel < ActiveRecord::Migration[7.2]
  # Don't imagine you'd want to revert this migration.
  def up
    Photo
      .where.not(learning_module_id: nil)
      .each do |photo|
        next unless photo.image.attached?

        LearningModule
          .find(photo.learning_module_id)
          .gallery
          .attach(photo.image.blob)
      end

    RepoFile
      .where.not(learning_module_id: nil)
      .each do |repo_file|
        next unless repo_file.file.attached?

        LearningModule
          .find(repo_file.learning_module_id)
          .project_files
          .attach(repo_file.file.blob)
      end

    Video
      .where.not(learning_module_id: nil)
      .each do |video|
        next unless video.video.attached?

        video.video.each do |vid|
          LearningModule
            .find(video.learning_module_id)
            .video_files
            .attach(vid.blob)
        end
      end

    Photo.where.not(learning_module_id: nil).destroy_all
    RepoFile.where.not(learning_module_id: nil).destroy_all
    Video.where.not(learning_module_id: nil).destroy_all
  end
end
