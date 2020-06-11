class AddDirectUploadUrlToVideos < ActiveRecord::Migration
  def change
    change_table :videos do |t|
      t.string :direct_upload_url, null: false
      t.boolean :processed, default: false, null: false
    end
  end
end
