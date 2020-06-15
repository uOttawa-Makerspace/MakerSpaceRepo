# frozen_string_literal: true

class AddApprovedToVolunteerHours < ActiveRecord::Migration[5.0]
  def change
    add_column :volunteer_hours, :approval, :boolean
  end
end
