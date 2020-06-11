# frozen_string_literal: true

class AddDirectUploadUrlToVideos < ActiveRecord::Migration[5.0]
  def change
    change_table :videos do |t|
      t.string :direct_upload_url, null: false
      t.boolean :processed, default: false, null: false
    end
  end
end
