class CreateChatMessages < ActiveRecord::Migration[7.2]
  def change
    unless table_exists?(:chat_messages)
      create_table :chat_messages do |t|
        t.text :message
        t.bigint :job_order_id
        t.bigint :sender_id
        t.boolean :is_read, default: false

        t.timestamps
      end

      add_foreign_key :chat_messages, :job_orders, column: :job_order_id
      add_foreign_key :chat_messages, :users, column: :sender_id
      add_index :chat_messages, :job_order_id
      add_index :chat_messages, :sender_id
    end

    # Add assigned staff to job_orders table
    unless column_exists?(:job_orders, :assigned_staff_id)
      add_column :job_orders, :assigned_staff_id, :bigint
      add_foreign_key :job_orders, :users, column: :assigned_staff_id
      add_index :job_orders, :assigned_staff_id
    end

    # Migrate existing comments to chat messages
    reversible do |dir|
      dir.up do
        JobOrder.where.not(comments: [nil, '']).find_each do |job_order|
          ChatMessage.create!(
            message: job_order.comments,
            job_order_id: job_order.id,
            sender_id: job_order.user_id,
            created_at: job_order.created_at,
            updated_at: job_order.updated_at
          )
        end

        JobOrder.where.not(user_comments: [nil, '']).find_each do |job_order|
          ChatMessage.create!(
            message: job_order.user_comments,
            job_order_id: job_order.id,
            sender_id: 25, # Justine :)
            created_at: job_order.created_at + 1.hour,
            updated_at: job_order.updated_at + 1.hour
          )
        end
      end
    end
  end
end