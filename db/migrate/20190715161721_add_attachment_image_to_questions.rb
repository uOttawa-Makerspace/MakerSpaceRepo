# frozen_string_literal: true

class AddAttachmentImageToQuestions < ActiveRecord::Migration[5.0]
  def self.up
    change_table :questions do |t|
      t.attachment :image
    end
  end

  def self.down
    remove_attachment :questions, :image
  end
end
