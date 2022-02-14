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

    reversible do |change|
      change.up do
        JobService.create(name: 'Low Quality', required: false, job_service_group: JobServiceGroup.find_by(name: 'PLA'), unit: 'g', internal_price: 1, external_price: 2)
        JobService.create(name: 'Medium Quality', required: false, job_service_group: JobServiceGroup.find_by(name: 'PLA'), unit: 'g', internal_price: 1, external_price: 2)
        JobService.create(name: 'High Quality', required: false, job_service_group: JobServiceGroup.find_by(name: 'PLA'), unit: 'g', internal_price: 1, external_price: 2)
        JobService.create(name: 'Low Quality', required: false, job_service_group: JobServiceGroup.find_by(name: 'ABS'), unit: 'g', internal_price: 1, external_price: 2)
        JobService.create(name: 'Medium Quality', required: false, job_service_group: JobServiceGroup.find_by(name: 'ABS'), unit: 'g', internal_price: 1, external_price: 2)
        JobService.create(name: 'High Quality', required: false, job_service_group: JobServiceGroup.find_by(name: 'ABS'), unit: 'g', internal_price: 1, external_price: 2)
        JobService.create(name: 'SST', required: false, job_service_group: JobServiceGroup.find_by(name: 'Dimension SST'), unit: 'h', internal_price: 15, external_price: 30)
        JobService.create(name: 'M2 Onyx', required: true, job_service_group: JobServiceGroup.find_by(name: 'Markforged'), unit: 'cm3', internal_price: 1, external_price: 2)
        JobService.create(name: 'M2 Fiber Glass', required: false, job_service_group: JobServiceGroup.find_by(name: 'Markforged'), unit: 'cm3', internal_price: 1, external_price: 2)
        JobService.create(name: 'M2 Carbon Fiber', required: false, job_service_group: JobServiceGroup.find_by(name: 'Markforged'), unit: 'cm3', internal_price: 1, external_price: 2)
      end
    end
  end
end
