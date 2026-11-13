class Admin::KeyTransactionsController < AdminAreaController
  before_action :set_key_transaction, only: %i[edit update show]

  def index
    @key_transactions = KeyTransaction.order(created_at: :desc)
  end

  def update
    if params.dig(:key_transaction, :deposit_return_date).blank?
      flash[:alert] = I18n.t("errors.admin.key_transactions.return_date_required")
    else
      flash_write(@key_transaction, "key_transactions.not_updated", I18n.t("admin_pages.key_transactions.flash.updated")) do
        @key_transaction.update(key_transaction_params)
      end
    end
    redirect_to admin_key_transactions_path
  end

  private

  def set_key_transaction
    @key_transaction = KeyTransaction.find_by(id: params[:id])

    if @key_transaction.nil?
      redirect_to admin_key_transactions_path,
                  alert: I18n.t("admin_pages.key_transactions.flash.not_found")
    end
  end

  def key_transaction_params
    params.require(:key_transaction).permit(:deposit_return_date)
  end
end
