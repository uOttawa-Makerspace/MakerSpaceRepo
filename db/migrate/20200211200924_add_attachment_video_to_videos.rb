class AddAttachmentVideoToVideos < ActiveRecord::Migration
  def self.up
    change_table :videos do |t|
      t.attachment :video
    end
  end

  def self.down
    remove_attachment :videos, :video
  end
end
