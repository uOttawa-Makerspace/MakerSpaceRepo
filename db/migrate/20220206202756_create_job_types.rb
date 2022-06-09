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
        JobType.create(name: '3D Print', description: 'Submit a file to be 3D Printed in our MakerSpace', comments: '<div>Additional comments can be added in step 4.<br><br>Each additional file that needs to be put on a separate build platform/bed is an extra $5.</div>', service_fee: 10, multiple_files:  true)
        JobType.create(name: 'Laser Cut', description: 'Submit a file to be Laser Cutted in our MakerSpace', comments: '<div>Please verify on the <a href="https://makerstore.ca">MakerStore</a> that the material you want is available before ordering.<br>Additional comments can be added in step 4.<br><br>Each additional file that needs to be put on a separate build platform/bed is an extra $5.</div>', service_fee: 15, multiple_files:  true)
        JobType.create(name: 'Design Services', description: 'Create the design you want with the help of our employees', comments: 'Additional comments can be added in step 4.', service_fee: 15, multiple_files:  true)
      end
    end
  end
end
