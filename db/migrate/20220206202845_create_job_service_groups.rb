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
        JobServiceGroup.create(name: 'PLA', description: '', job_type: JobType.find_by(name: '3D Print'), multiple: false, text_field: false)
        JobServiceGroup.create(name: 'ABS', description: '', job_type: JobType.find_by(name: '3D Print'), multiple: false, text_field: false)
        JobServiceGroup.create(name: 'Dimension SST', description: '', job_type: JobType.find_by(name: '3D Print'), multiple: false, text_field: false)
        JobServiceGroup.create(name: 'Markforged', description: '', job_type: JobType.find_by(name: '3D Print'), multiple: true, text_field: false)
        JobServiceGroup.create(name: 'Other', description: '', job_type: JobType.find_by(name: '3D Print'), multiple: false, text_field: true)
      end
    end
  end
end
