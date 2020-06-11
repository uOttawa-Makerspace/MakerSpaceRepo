# frozen_string_literal: true

class CreateVolunteerRequests < ActiveRecord::Migration
  def change
    create_table :volunteer_requests do |t|
      t.text :interests, default: ''

      t.timestamps null: false
    end
  end
end
