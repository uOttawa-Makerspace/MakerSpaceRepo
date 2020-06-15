# frozen_string_literal: true

class YearOfStudy < ActiveRecord::Migration[5.0]
  def change
    add_column :users, :year_of_study, :string
  end
end
