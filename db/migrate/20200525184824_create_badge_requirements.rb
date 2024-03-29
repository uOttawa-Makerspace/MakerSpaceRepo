# frozen_string_literal: true

class CreateBadgeRequirements < ActiveRecord::Migration[5.0]
  def change
    create_table :badge_requirements do |t|
      t.timestamps null: false
      t.references :badge_template, index: true, foreign_key: true
      t.references :proficient_project, index: true, foreign_key: true
    end
  end
end
