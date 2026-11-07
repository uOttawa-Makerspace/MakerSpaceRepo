class ChatMessagesController < SessionsController
  before_action :signed_in

  def create
    order = JobOrder.not_deleted.find_by(id: chat_message_params[:job_order_id])
    return head :not_found unless order
    return head :forbidden unless can_access_order?(order)

    @chat_message = order.post_chat_message(chat_message_params[:message], current_user)

    return if @chat_message.persisted?
      flash[:error] = "Failed to send message: #{@chat_message.errors.full_messages.join(', ')}"    
  end

  def index
    @job_order = JobOrder.not_deleted.find(params[:job_order_id])
    return head :forbidden unless can_access_order?(@job_order)

    @chat_messages = @job_order.chat_messages.includes(:sender).order(created_at: :desc)

    render partial: 'chat_messages/message', collection: @chat_messages, as: :chat_message
  end

  private

  # Same audience as JobOrdersController#set_job_order: owner, staff or admin.
  def can_access_order?(order)
    order.accessible_by?(current_user)
  end

  def chat_message_params
    params.require(:chat_message).permit(:message, :job_order_id)
  end
end