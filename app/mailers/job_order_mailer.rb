class JobOrderMailer < ApplicationMailer
  def send_job_submitted(job_order_id)
    return unless JobOrder.where(id: job_order_id).present?
  @job_order = JobOrder.find(job_order_id)

  

    if @job_order.expedited?
      mail(
        to: "makerspace@uottawa.ca",
        subject: "EXPEDITED: A new Job Order has been submitted",
        Importance: "high",
        "X-Priority": "1"
      )
    else
      mail(
        to: "makerspace@uottawa.ca",
        subject: "A new Job Order has been submitted"
      )
    end
  end

  def send_job_quote(job_order_id, reminder = false)
    return unless JobOrder.exists?(id: job_order_id)
    @job_order = JobOrder.find(job_order_id)

    @reminder = reminder
    @hash = Rails.application.message_verifier(:job_order_id).generate(job_order_id)

    approved_fr, approved_en =
      if @job_order.job_order_statuses.where(job_status: JobStatus::USER_APPROVAL).count > 1
        ["réapprouvée", "re-approved"]
      else
        ["approuvée", "approved"]
      end

    mail(
      to: @job_order.user.email,
      reply_to: "makerspace@uottawa.ca",
      bcc: "uottawa.makerepo@gmail.com",
      subject: "Votre commande ##{@job_order.id} a été #{approved_fr} // Your job order ##{@job_order.id} has been #{approved_en}"
    )
  end

  def send_job_declined(job_order_id)
    return unless JobOrder.where(id: job_order_id).present?
  @job_order = JobOrder.find(job_order_id)

  

    mail(
      to: @job_order.user.email,
      reply_to: "makerspace@uottawa.ca",
      bcc: "uottawa.makerepo@gmail.com",
      subject:
        "Your job ##{@job_order.id} (#{@job_order.user_files.first.filename}) has been declined"
    )
  end

  def send_job_user_approval(job_order_id)
    return unless JobOrder.where(id: job_order_id).present?
  @job_order = JobOrder.find(job_order_id)

  

    if @job_order.expedited?
      mail(
        to: "makerspace@uottawa.ca",
        subject: "EXPEDITED: A user has approved a Job Order",
        Importance: "high",
        "X-Priority": "1"
      )
    else
      mail(
        to: "makerspace@uottawa.ca",
        subject: "A user has approved a Job Order"
      )
    end
  end

  def send_job_completed(job_order_id, message)
    return unless JobOrder.where(id: job_order_id).present?
  @job_order = JobOrder.find(job_order_id)

  


    @message =
      if message.present?
        message.html_safe
      else
        JobOrderMessage
          .find_by(name: "processed")
          .retrieve_message(@job_order.id)
          .html_safe
      end

    mail(
      to: @job_order.user.email,
      reply_to: "makerspace@uottawa.ca",
      bcc: "uottawa.makerepo@gmail.com",
      subject: "Your Job Order ##{@job_order.id} has been completed"
    )
  end

  def payment_succeeded(job_order_id)
    return unless JobOrder.where(id: job_order_id).present?
  @job_order = JobOrder.find(job_order_id)

  

    mail(
      to: @job_order.user.email,
      reply_to: "makerspace@uottawa.ca",
      bcc: "uottawa.makerepo@gmail.com",
      subject: "Your Job Order ##{@job_order.id} is now ready for pickup"
    )
  end

  def payment_failed(job_order_id)
    return unless JobOrder.where(id: job_order_id).present?
  @job_order = JobOrder.find(job_order_id)

  

    mail(
      to: @job_order.user.email,
      reply_to: "makerspace@uottawa.ca",
      bcc: "uottawa.makerepo@gmail.com",
      subject: "Your Job Order Payment has failed for Order ##{@job_order.id}"
    )
  end

  def staff_assigned(job_order_id, staff_member_id)
    return if JobOrder.where(id: job_order_id).blank?
      @job_order = JobOrder.find(job_order_id)
    
    @staff_member = User.find(staff_member_id)
    
    if @job_order.expedited?
      mail(
        to: @staff_member.email,
        subject: "EXPEDITED: You've been assigned to Job Order ##{@job_order.id}",
        Importance: "high",
        "X-Priority": "1"
      )
    else
      mail(
        to: @staff_member.email,
        subject: "You've been assigned to Job Order ##{@job_order.id}"
      )
    end

    logger.warn "YOU'VE GOT MAIL #{@staff_member.inspect}"
  end

  # def send_print_reminder(email, id)
  #   mail(to: email, subject: "Reminder for your print order ##{id}")
  # end
end
