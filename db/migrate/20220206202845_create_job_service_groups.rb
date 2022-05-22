class CreateJobServiceGroups < ActiveRecord::Migration[6.1]
  def change
    create_table :job_service_groups do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :multiple, default: false
      t.boolean :text_field, default: false
      t.references :job_type, null: false, index: true, foreign_key: true
      t.timestamps
    end

    reversible do |change|
      change.up do
        JobServiceGroup.create(name: 'PLA', description: 'Most commonly used material in 3D Printers', job_type: JobType.find_by(name: '3D Print'), multiple: false, text_field: false)
        JobServiceGroup.create(name: 'ABS', description: 'Stronger than PLA', job_type: JobType.find_by(name: '3D Print'), multiple: false, text_field: false)
        JobServiceGroup.create(name: 'Dimension SST', description: 'Printer that uses ABS and soluble supports', job_type: JobType.find_by(name: '3D Print'), multiple: false, text_field: false)
        JobServiceGroup.create(name: 'Markforged', description: 'Filament with Nylon and chopped parts of carbon fiber', job_type: JobType.find_by(name: '3D Print'), multiple: true, text_field: false)
        JobServiceGroup.create(name: 'Other', description: 'Please enter the type of material you would like and we\'ll get back to you', job_type: JobType.find_by(name: '3D Print'), multiple: false, text_field: true)
        JobServiceGroup.create(name: 'MDF', description: 'Fiber board', job_type: JobType.find_by(name: 'Laser Cut'), multiple: false, text_field: false)
        JobServiceGroup.create(name: '1/8" Acrylic', description: '1/8 inch acrylic sheet', job_type: JobType.find_by(name: 'Laser Cut'), multiple: false, text_field: false)
        JobServiceGroup.create(name: '1/4" Acrylic', description: '1/4 inch acrylic sheet', job_type: JobType.find_by(name: 'Laser Cut'), multiple: false, text_field: false)
        JobServiceGroup.create(name: 'Other material', description: 'Please enter the type of material you would like and we\'ll get back to you', job_type: JobType.find_by(name: 'Laser Cut'), multiple: false, text_field: true)
      end
    end
  end
end
