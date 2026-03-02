class CreateHelps < ActiveRecord::Migration[7.2]
  def change
    create_table :helps do |t|
      t.string :gh_issue_number

      t.timestamps
    end
  end
end
