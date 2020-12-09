class AddCertificationToBadges < ActiveRecord::Migration[6.0]
  def change
    add_reference :badges, :certification, index: true, foreign_key: true
  end
end
