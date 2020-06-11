# frozen_string_literal: true

class AddAttachmentFileToRepoFiles < ActiveRecord::Migration[5.0]
  def change
    change_table :repo_files do |t|
      t.attachment :file
    end
  end
end
