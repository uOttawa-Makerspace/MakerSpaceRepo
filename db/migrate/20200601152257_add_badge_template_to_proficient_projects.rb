# frozen_string_literal: true

class AddBadgeTemplateToProficientProjects < ActiveRecord::Migration[5.0]
  def change
    add_reference :proficient_projects, :badge_template, index: true, foreign_key: true
  end
end
