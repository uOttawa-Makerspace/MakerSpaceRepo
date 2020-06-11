# frozen_string_literal: true

class AddExpiredAtToExams < ActiveRecord::Migration[5.0]
  def change
    add_column :exams, :expired_at, :datetime
  end
end
