class CreateJobTypes < ActiveRecord::Migration[6.1]
  def change
    create_table :job_types do |t|
      t.string :name, null: false
      t.boolean :multiple_files, default: false, null: false
      t.string :file_label, default: 'File'
      t.text :file_description
      t.decimal :service_fee, precision: 10, scale: 2
      t.timestamps
    end

    reversible do |change|
      change.up do
        JobType.create(name: '3D Print', service_fee: 10)
        JobType.create(name: 'Laser Cut', service_fee: 15)
        JobType.create(name: 'Design Services', service_fee: 15)
      end
    end
  end
end
