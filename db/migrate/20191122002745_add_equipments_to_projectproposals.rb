# frozen_string_literal: true

class AddEquipmentsToProjectproposals < ActiveRecord::Migration[5.0]
  def change
    add_column :project_proposals, :equipments, :text, default: 'Not informed.'
  end
end
