class JobOrderMailer < ApplicationMailer

  def send_job_submitted(job_order_id)
    JobOrder.where(id: job_order_id).present? ? @job_order = JobOrder.find(job_order_id) : return
    if @job_order.expedited?
      mail(to: 'makerspace@uottawa.ca', subject: 'EXPEDITED: A new Job Order has been submitted', 'Importance': 'high', 'X-Priority': '1')
    else
      mail(to: 'makerspace@uottawa.ca', subject: 'A new Job Order has been submitted')
    end
  end

  # TODO: Change design of this email
  # def send_job_quote(expedited_price, user, print_order, comments, clean_part_price, resend)
  #   @clean_part_price = clean_part_price
  #   @expedited_price = expedited_price
  #   @user = user
  #   @print_order = print_order
  #   @comments = comments
  #   @resend = resend
  #   mail(to: @user.email, reply_to: 'makerspace@uottawa.ca', bcc: 'uottawa.makerepo@gmail.com', subject: "Your print \"#{@print_order.file.filename}\" has been approved!")
  # end

  # def send_job_declined(user, comments, filename)
  #   @user = user
  #   @comments = comments
  #   @filename = filename
  #   mail(to: @user.email, reply_to: 'makerspace@uottawa.ca', bcc: 'uottawa.makerepo@gmail.com', subject: "Your print \"#{filename}\" has been denied")
  # end
  #
  # def send_job_user_approval(id)
  #   @print_id = id
  #   if PrintOrder.find(id).expedited?
  #     mail(to: 'makerspace@uottawa.ca', subject: 'EXPEDITED: A user has approved a print order', 'Importance': 'high', 'X-Priority': '1')
  #   else
  #     mail(to: 'makerspace@uottawa.ca', subject: 'A user has approved a print order')
  #   end
  # end
  #
  # def send_job_processed(user, pickup_id, quote, message)
  #   @quote = quote
  #   @user = user
  #   @pickup_id = pickup_id
  #   @message = message.html_safe
  #   mail(to: @user.email, reply_to: 'makerspace@uottawa.ca', bcc: 'uottawa.makerepo@gmail.com', subject: 'Your print is available for pickup')
  # end
  #
  # def send_print_reminder(email, id)
  #   mail(to: email, subject: "Reminder for your print order ##{id}")
  # end
end
