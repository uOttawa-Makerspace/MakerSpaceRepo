# frozen_string_literal: true

class CreateCertifications < ActiveRecord::Migration
  def change
    create_table :certifications do |t|
      t.references :user, index: true, foreign_key: true
      t.string :name

      t.timestamps null: false
    end
  end
end
