class CreateJobServices < ActiveRecord::Migration[6.1]
  def change
    create_table :job_services do |t|
      t.string :name, null: false
      t.text :description
      t.string :unit
      t.boolean :required, default: false, null: false
      t.decimal :internal_price, precision: 10, scale: 2
      t.decimal :external_price, precision: 10, scale: 2
      t.references :job_service_group, null: false, index: true, foreign_key: true
      t.timestamps
    end

    reversible do |change|
      change.up do
        JobService.create(name: 'Low Quality', description: '(Short time and small price, 0.3mm Layer Height, 15% infill, supports if needed)', required: false, job_service_group: JobServiceGroup.find_by(name: 'PLA'), unit: 'g', internal_price: 0.15, external_price: 0.3)
        JobService.create(name: 'Medium Quality', description: '(Medium time and medium price, 0.2mm Layer Height, 15% infill, supports if needed)', required: false, job_service_group: JobServiceGroup.find_by(name: 'PLA'), unit: 'g', internal_price: 0.2, external_price: 0.4)
        JobService.create(name: 'High Quality', description: '(Longer time, more expensive, 0.1mm Layer Height, 20% infill, supports if needed)', required: false, job_service_group: JobServiceGroup.find_by(name: 'PLA'), unit: 'g', internal_price: 0.25, external_price: 0.5)
        JobService.create(name: 'Low Quality', description: '(Short time and small price, 0.3mm Layer Height, 15% infill, supports if needed)', required: false, job_service_group: JobServiceGroup.find_by(name: 'ABS'), unit: 'g', internal_price: 0.15, external_price: 0.3)
        JobService.create(name: 'Medium Quality', description: '(Medium time and medium price, 0.2mm Layer Height, 15% infill, supports if needed)', required: false, job_service_group: JobServiceGroup.find_by(name: 'ABS'), unit: 'g', internal_price: 0.2, external_price: 0.4)
        JobService.create(name: 'High Quality', description: '(Long time, more expensive, 0.1mm Layer Height, 20% infill, supports if needed)', required: false, job_service_group: JobServiceGroup.find_by(name: 'ABS'), unit: 'g', internal_price: 0.25, external_price: 0.5)
        JobService.create(name: 'SST', required: false, job_service_group: JobServiceGroup.find_by(name: 'Dimension SST'), unit: 'h', internal_price: 15, external_price: 30)
        JobService.create(name: 'M2 Onyx', description: 'Basic filament used with the MarkForged Printers.', required: true, job_service_group: JobServiceGroup.find_by(name: 'Markforged'), unit: 'cm3', internal_price: 0.53, external_price: 0.53)
        JobService.create(name: 'M2 Fiber Glass', description: 'Fiber Glass Filament that will be added with the Onyx Filament.', required: false, job_service_group: JobServiceGroup.find_by(name: 'Markforged'), unit: 'cm3', internal_price: 5.82, external_price: 5.82)
        JobService.create(name: 'M2 Carbon Fiber', description: 'Carbon Fiber Filament that will be added with the Onyx Filament.', required: false, job_service_group: JobServiceGroup.find_by(name: 'Markforged'), unit: 'cm3', internal_price: 2.99, external_price: 2.99)
        JobService.create(name: '1/8"', required: false, job_service_group: JobServiceGroup.find_by(name: 'MDF'), unit: 'piece', internal_price: 3, external_price: 3)
        JobService.create(name: '1/4"', required: false, job_service_group: JobServiceGroup.find_by(name: 'MDF'), unit: 'piece', internal_price: 4, external_price: 4)
        JobService.create(name: 'White', required: false, job_service_group: JobServiceGroup.find_by(name: '1/8" Acrylic'), unit: 'piece', internal_price: 15, external_price: 15)
        JobService.create(name: 'Black', required: false, job_service_group: JobServiceGroup.find_by(name: '1/8" Acrylic'), unit: 'piece', internal_price: 15, external_price: 15)
        JobService.create(name: 'Clear', required: false, job_service_group: JobServiceGroup.find_by(name: '1/8" Acrylic'), unit: 'piece', internal_price: 15, external_price: 15)
        JobService.create(name: 'White', required: false, job_service_group: JobServiceGroup.find_by(name: '1/4" Acrylic'), unit: 'piece', internal_price: 18, external_price: 18)
        JobService.create(name: 'Black', required: false, job_service_group: JobServiceGroup.find_by(name: '1/4" Acrylic'), unit: 'piece', internal_price: 18, external_price: 18)
        JobService.create(name: 'Clear', required: false, job_service_group: JobServiceGroup.find_by(name: '1/4" Acrylic'), unit: 'piece', internal_price: 18, external_price: 18)
      end
    end
  end
end
