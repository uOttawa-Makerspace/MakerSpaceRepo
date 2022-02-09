class CreateJobTypes < ActiveRecord::Migration[6.1]
  def change
    create_table :job_types do |t|
      t.string :name, null: false
      t.boolean :multiple_files, default: false, null: false
      t.string :file_label, default: 'File'
      t.text :file_description
      t.timestamps
    end

    JobType.create(name: '3D Print')
    JobType.create(name: 'Laser Cut')
    JobType.create(name: 'Design Services')
  end
end
