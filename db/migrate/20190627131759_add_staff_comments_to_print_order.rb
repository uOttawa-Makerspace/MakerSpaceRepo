# frozen_string_literal: true

class AddStaffCommentsToPrintOrder < ActiveRecord::Migration[5.0]
  def change
    add_column :print_orders, :StaffComments, :text
  end
end
