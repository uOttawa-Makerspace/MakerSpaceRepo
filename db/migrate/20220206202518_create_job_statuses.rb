class CreateJobStatuses < ActiveRecord::Migration[6.1]
  def change
    create_table :job_statuses do |t|
      t.string :name, null: false
      t.text :description
      t.timestamps
    end

    reversible do |change|
      change.up do
        JobStatus.create(name: 'Partially created', description: 'Job has been created but not all of its parts have been created yet.')
        JobStatus.create(name: 'Waiting for Staff Approval', description: 'Waiting for Staff Approval')
        JobStatus.create(name: 'Waiting for User Approval', description: 'Waiting for User Approval')
        JobStatus.create(name: 'Waiting for to be Processed', description: 'Waiting for to be Processed')
        JobStatus.create(name: 'Processed', description: 'Processed')
        JobStatus.create(name: 'Declined', description: 'Declined')
      end
    end
  end
end
