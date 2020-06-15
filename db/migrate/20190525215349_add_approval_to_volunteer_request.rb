# frozen_string_literal: true

class AddApprovalToVolunteerRequest < ActiveRecord::Migration[5.0]
  def change
    add_column :volunteer_requests, :approval, :boolean
  end
end
