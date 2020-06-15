# frozen_string_literal: true

class AddStatusToExams < ActiveRecord::Migration[5.0]
  def change
    add_column :exams, :status, :string, default: 'not started'
  end
end
