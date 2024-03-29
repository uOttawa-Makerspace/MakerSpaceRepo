# frozen_string_literal: true

class AddReferenceToBadge < ActiveRecord::Migration[5.0]
  def change
    add_reference :badges, :badge_template, index: true, foreign_key: true
  end
end
