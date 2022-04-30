class CreateJobStatuses < ActiveRecord::Migration[6.1]
  def change
    create_table :job_statuses do |t|
      t.string :name, null: false
      t.text :description
      t.timestamps
    end

    reversible do |change|
      change.up do
        JobStatus.create(name: 'Draft', description: 'The job is a draft and has not yet be sent for approval.')
        JobStatus.create(name: 'Waiting for Staff Approval', description: 'The job has been sent for Staff Approval')
        JobStatus.create(name: 'Waiting for User Approval', description: 'Currently waiting for the user to approve the job.')
        JobStatus.create(name: 'Waiting to be Processed', description: 'Waiting for the job to be processed or sent to manufacturing.')
        JobStatus.create(name: 'Processed', description: 'The job has been processed')
        JobStatus.create(name: 'Paid', description: 'The client has paid for the job.')
        JobStatus.create(name: 'Picked-Up', description: 'The client has picked up the job.')
        JobStatus.create(name: 'Declined', description: 'The job has been cancelled by the client or staff.')
      end
    end
  end
end
