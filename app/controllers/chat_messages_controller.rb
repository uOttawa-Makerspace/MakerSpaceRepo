class ChatMessagesController < SessionsController
  before_action :signed_in

  def create
    order = JobOrder.not_deleted.find_by(id: chat_message_params[:job_order_id])
    return head :forbidden if order && !can_access_order?(order)

    @chat_message = ChatMessage.new(chat_message_params)
    @chat_message.job_order = order
    @chat_message.sender = current_user

    return if @chat_message.save
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
    current_user.admin? || current_user.staff? || current_user.id == order.user_id
  end

  def chat_message_params
    params.require(:chat_message).permit(:message, :job_order_id)
  end
end