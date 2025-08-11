class CreateStaffExternalUnavailabilities < ActiveRecord::Migration[7.2]
  def change
    create_table :staff_external_unavailabilities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ics_url

      t.timestamps
    end
  end
end
