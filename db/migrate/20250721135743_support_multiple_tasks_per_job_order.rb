class SupportMultipleTasksPerJobOrder < ActiveRecord::Migration[7.2]
  def change
    create_table :job_tasks do |t|
      t.references :job_order, null: false, foreign_key: true
      t.references :job_type, foreign_key: true
      t.references :job_service, foreign_key: true
      t.string     :title, default: ""
      t.timestamps
    end

    create_table :job_task_options do |t|
      t.references :job_task, null: false, foreign_key: true
      t.references :job_option, null: false, foreign_key: true
      t.timestamps
    end

    create_table :job_task_quotes do |t|
      t.references :job_task, null: false, foreign_key: true
      t.decimal :price, precision: 10, scale: 2
      t.timestamps
    end

    create_table :job_task_quote_options do |t|
      t.references :job_task_quote, null: false, foreign_key: true
      t.references :job_option, null: false, foreign_key: true
      t.decimal :price, precision: 10, scale: 2
      t.timestamps
    end

    create_table :job_task_quote_services do |t|
      t.references :job_task_quote, null: false, foreign_key: true
      t.references :job_service, null: false, foreign_key: true
      t.decimal :quantity, precision: 10, default: 1
      t.decimal :price, precision: 10, scale: 2
      t.timestamps
    end

    create_table :job_quote_line_items do |t|
      t.references :job_order, null: false, foreign_key: true
      t.string :description, null: false
      t.decimal :price, precision: 10, scale: 2
      t.timestamps
    end

    reversible do |dir|
      dir.up do
        say_with_time "Seeding job_tasks for existing job_orders..." do
          JobOrder.reset_column_information
          JobOrder.find_each do |order|
            task = JobTask.create!(
              job_order_id: order.id,
              job_type_id: order.job_type_id,
              job_service_id: order.job_services.first&.id,
              title: "Main Task"
            )

            # Migrate options
            order.job_order_options.each do |job_order_option|
              task.job_task_options.create!(job_option_id: job_order_option.job_option_id)
            end

            # Reattach user files
            order.user_files.each do |attachment|
              task.user_files.attach(attachment.blob)
            end

            # Reattach staff files
            order.staff_files.each do |attachment|
              task.staff_files.attach(attachment.blob)
            end

            # Create a quote scaffold for the task if old quote exists
            if order.job_order_quote
              task_quote = JobTaskQuote.create!(
                job_task_id: task.id,
                price: order.job_order_quote.service_fee || 0
              )

              # Migrate quote options
              if order.job_order_quote.respond_to?(:job_order_quote_options)
                order.job_order_quote.job_order_quote_options.each do |opt|
                  JobTaskQuoteOption.create!(
                    job_task_quote_id: task_quote.id,
                    job_option_id: opt.job_option_id,
                    price: opt.amount
                  )
                end
              end

              # Migrate quote services
              if order.job_order_quote.respond_to?(:job_order_quote_services)
                order.job_order_quote.job_order_quote_services.each do |svc|
                  JobTaskQuoteService.create!(
                    job_task_quote_id: task_quote.id,
                    job_service_id: svc.job_service_id,
                    quantity: svc.quantity,
                    price: svc.per_unit
                  )
                end
              end
            end
          end
        end
      end
    end
  end
end
