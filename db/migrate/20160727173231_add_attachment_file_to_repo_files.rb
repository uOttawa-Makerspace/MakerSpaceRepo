class AddAttachmentFileToRepoFiles < ActiveRecord::Migration
  def change
    change_table :repo_files do |t|
      t.attachment :file
    end
  end
end
