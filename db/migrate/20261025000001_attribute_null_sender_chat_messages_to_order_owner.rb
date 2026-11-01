# A chat message needs a sender. Rows stored without one are attributed to the job
# order's owner. Idempotent: only touches rows that still have a NULL sender.
class AttributeNullSenderChatMessagesToOrderOwner < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE chat_messages
      SET sender_id = job_orders.user_id
      FROM job_orders
      WHERE chat_messages.job_order_id = job_orders.id
        AND chat_messages.sender_id IS NULL
        AND job_orders.user_id IS NOT NULL
    SQL
  end

  def down
    # Irreversible by design: once attributed, the rows that were NULL cannot
    # be told apart from messages the owner really wrote. Nothing to undo.
  end
end
