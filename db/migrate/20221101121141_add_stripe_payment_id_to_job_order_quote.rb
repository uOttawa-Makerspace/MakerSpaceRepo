class AddStripePaymentIdToJobOrderQuote < ActiveRecord::Migration[6.1]
  def change
    add_column :job_order_quotes, :stripe_transaction_id, :string
  end
end
