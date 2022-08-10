class CreateJobTypeExtras < ActiveRecord::Migration[6.1]
  def change
    create_table :job_type_extras do |t|
      t.references :job_type, index: true, foreign_key: true
      t.string :name
      t.decimal :price, precision: 10, scale: 2
      t.timestamps
    end

    reversible do |change|
      change.up do
        JobTypeExtra.create(
          name: "Machine Costs",
          job_type: JobType.find_by(name: "Laser Cut")
        )
      end
    end
  end
end
