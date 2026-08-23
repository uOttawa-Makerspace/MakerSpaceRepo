class AddPolymorphicHolderToKeysAndTransactions < ActiveRecord::Migration[8.1]
  def change
    add_reference :keys, :holder, polymorphic: true, index: true
    add_reference :key_transactions, :holder, polymorphic: true, index: true

    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE keys
          SET holder_type = 'User', holder_id = user_id
          WHERE user_id IS NOT NULL;

          UPDATE key_transactions
          SET holder_type = 'User', holder_id = user_id
          WHERE user_id IS NOT NULL;
        SQL
      end
    end
  end
end