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

    reversible do |change|
      change.up do
        JobOption.create(name: "Expedited", description: "Expedited Job (Extra Charge)", need_files: false, fee: 20, job_type_ids: JobType.all.pluck(:id))
        JobOption.create(name: "Clean Off Part", description: "Remove Supports (Extra Charge)", need_files: false, fee: 5, job_type_ids: [JobType.find_by(name: "3D Print").id])
        JobOption.create(name: "Competitive Team", description: "If you are in a competitive team please submit your signed off drawing for this part. (It needs to be a PDF)", need_files: true, fee: 0, job_type_ids: JobType.all.pluck(:id))
      end
    end
  end
end
