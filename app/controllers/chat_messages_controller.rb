class ChatMessagesController < SessionsController
  def create
    @chat_message = ChatMessage.new(chat_message_params)
    @chat_message.sender = current_user

    return if @chat_message.save
      flash[:error] = "Failed to send message: #{@chat_message.errors.full_messages.join(', ')}"    
  end

  def index
    @job_order = JobOrder.find(params[:job_order_id])
    @chat_messages = @job_order.chat_messages.includes(:sender).order(created_at: :desc)

    render partial: 'chat_messages/message', collection: @chat_messages, as: :chat_message
  end

  private

  def chat_message_params
    params.require(:chat_message).permit(:message, :job_order_id)
  end
end