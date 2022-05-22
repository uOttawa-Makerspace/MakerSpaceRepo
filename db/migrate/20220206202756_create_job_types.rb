class CreateJobTypes < ActiveRecord::Migration[6.1]
  def change
    create_table :job_types do |t|
      t.string :name, null: false
      t.text :description
      t.text :comments
      t.boolean :multiple_files, default: false, null: false
      t.string :file_label, default: 'File'
      t.text :file_description
      t.decimal :service_fee, precision: 10, scale: 2
      t.timestamps
    end

    reversible do |change|
      change.up do
        JobType.create(name: '3D Print', description: 'Submit a file to be 3D Printed in our MakerSpace', comments: 'Additional comments can be added in step 4.', service_fee: 10)
        JobType.create(name: 'Laser Cut', description: 'Submit a file to be Laser Cutted in our MakerSpace', comments: '<div>Please verify on the <a href="https://makerstore.ca">MakerStore</a>&nbsp;that the material you want is available before ordering.</div>', service_fee: 15)
        JobType.create(name: 'Design Services', description: 'Create the design you want with the help of our employees', comments: 'Additional comments can be added in step 4.', service_fee: 15)
      end
    end
  end
end
