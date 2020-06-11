# frozen_string_literal: true

class AddSpaceToTrainings < ActiveRecord::Migration
  def change
    add_reference :trainings, :space, index: true, foreign_key: true
  end
end
