class AddSentReminderStatusToJobOrders < ActiveRecord::Migration[6.1]
  def change
    add_column :job_orders, :is_deleted, :boolean, default: false

    reversible do |change|
      change.up do
        JobStatus.create(
          name: "Sent a Quote Reminder",
          description:
            "Currently waiting for the user to approve the job, a quote reminder has been re-sent."
        )
      end
    end
  end
end
