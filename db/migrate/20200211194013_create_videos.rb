class CreateVideos < ActiveRecord::Migration
  def change
    create_table :videos do |t|
      t.string :video_file_name
      t.string :video_content_type
      t.integer :video_file_size
      t.datetime :video_updated_at

      t.timestamps null: false
    end
  end
end
