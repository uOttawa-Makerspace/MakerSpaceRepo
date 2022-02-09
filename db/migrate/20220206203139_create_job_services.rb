class CreateJobServices < ActiveRecord::Migration[6.1]
  def change
    create_table :job_services do |t|
      t.string :name, null: false
      t.text :description
      t.string :unit, null: false
      t.boolean :required, default: false, null: false
      t.decimal :internal_price, precision: 10, scale: 2, null: false
      t.decimal :external_price, precision: 10, scale: 2, null: false
      t.references :job_service_group, null: false, index: true, foreign_key: true
      t.timestamps
    end
  end
end
