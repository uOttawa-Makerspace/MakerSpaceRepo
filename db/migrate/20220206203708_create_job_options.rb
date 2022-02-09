class CreateJobOptions < ActiveRecord::Migration[6.1]
  def change
    create_table :job_options do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :need_files, null: false, default: false
      t.decimal :fee, precision: 10, scale: 2, null: false
      t.timestamps
    end

    create_join_table :job_types, :job_options do |t|
      t.index :job_option_id
      t.index :job_type_id
    end
  end
end
