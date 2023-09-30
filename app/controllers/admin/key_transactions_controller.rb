class Admin::KeyTransactionsController < AdminAreaController
  before_action :set_key_transaction, only: %i[edit update show]

  def index
    @key_transactions = KeyTransaction.order(created_at: :desc)
  end

  def update
    if !params[:key_transaction][:deposit_return_date].empty? &&
         @key_transaction.update(key_transaction_params)
      redirect_to admin_key_transactions_path,
                  notice: "Successfully updated deposit information"
    else
      redirect_to admin_key_transactions_path,
                  alert: "Something went wrong while updating the deposit"
    end
  end

  private

  def set_key_transaction
    @key_transaction = KeyTransaction.find_by(id: params[:id])

    if @key_transaction.nil?
      redirect_to admin_key_transactions_path,
                  alert: "Key Transaction was not found"
    end
  end

  def key_transaction_params
    params.require(:key_transaction).permit(:deposit_return_date)
  end
end
