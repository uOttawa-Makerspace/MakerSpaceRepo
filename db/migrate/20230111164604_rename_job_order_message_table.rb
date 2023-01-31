class RenameJobOrderMessageTable < ActiveRecord::Migration[6.1]
  def up
    rename_table :print_order_messages, :job_order_messages
    JobOrderMessage.where(name: "I_Printed_It").update(name: "processed")
  end

  def down
    JobOrderMessage.where(name: "processed").update(name: "I_Printed_It")
    rename_table :job_order_messages, :print_order_messages
  end
end
