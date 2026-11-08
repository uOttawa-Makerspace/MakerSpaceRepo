module ChatMessagesHelper
  # Who wrote a chat message, as the viewer should see it. Staff and admins see a deleted
  # account's real name marked as deleted; everyone else sees a neutral label.
  def chat_sender_label(chat_message, viewer)
    return 'You' if chat_message.sender_id == viewer.id

    sender = chat_message.display_sender
    return 'Unknown' if sender.nil?
    return staff_user_name(sender) if viewer.staff?

    sender.deleted? ? t('users.deleted_user') : sender.name
  end

  # The "(staff)" tag goes after the name of another, live staff member.
  def chat_sender_staff?(chat_message, viewer)
    sender = chat_message.display_sender
    chat_message.sender_id != viewer.id && sender.present? && !sender.deleted? && sender.staff?
  end
end
