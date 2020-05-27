class AddReferenceToBadge < ActiveRecord::Migration
  def change
    add_reference :badges, :badge_template, index: true, foreign_key: true
  end
end
