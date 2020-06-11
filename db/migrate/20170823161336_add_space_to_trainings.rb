# frozen_string_literal: true

class AddSpaceToTrainings < ActiveRecord::Migration[5.0]
  def change
    add_reference :trainings, :space, index: true, foreign_key: true
  end
end
