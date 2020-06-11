# frozen_string_literal: true

class AddExpiredAtToExams < ActiveRecord::Migration
  def change
    add_column :exams, :expired_at, :datetime
  end
end
