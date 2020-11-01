class AddDropOffLocationToProficientProject < ActiveRecord::Migration[6.0]
  def change
    add_reference :proficient_projects, :drop_off_location, foreign_key: true
  end
end
