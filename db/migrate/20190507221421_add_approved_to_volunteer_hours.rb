# frozen_string_literal: true

class AddApprovedToVolunteerHours < ActiveRecord::Migration
  def change
    add_column :volunteer_hours, :approval, :boolean
  end
end
