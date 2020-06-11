# frozen_string_literal: true

class ChangeDefaultOfVolunteerRequest < ActiveRecord::Migration
  def up
    change_column :volunteer_requests, :printing, :string, default: 'No Experience'
    change_column :volunteer_requests, :laser_cutting, :string, default: 'No Experience'
    change_column :volunteer_requests, :virtual_reality, :string, default: 'No Experience'
    change_column :volunteer_requests, :arduino, :string, default: 'No Experience'
    change_column :volunteer_requests, :embroidery, :string, default: 'No Experience'
  end

  def down
    change_column :volunteer_requests, :printing, :string
    change_column :volunteer_requests, :laser_cutting, :string
    change_column :volunteer_requests, :virtual_reality, :string
    change_column :volunteer_requests, :arduino, :string
    change_column :volunteer_requests, :embroidery, :string
  end
end
