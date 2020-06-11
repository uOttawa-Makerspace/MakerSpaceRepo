# frozen_string_literal: true

class AddStatusToExams < ActiveRecord::Migration
  def change
    add_column :exams, :status, :string, default: 'not started'
  end
end
