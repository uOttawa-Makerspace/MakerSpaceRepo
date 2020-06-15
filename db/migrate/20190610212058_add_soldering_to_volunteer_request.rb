# frozen_string_literal: true

class AddSolderingToVolunteerRequest < ActiveRecord::Migration[5.0]
  def change
    add_column :volunteer_requests, :soldering, :string, default: 'No Experience'
  end
end
