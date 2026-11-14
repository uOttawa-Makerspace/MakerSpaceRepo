class JobOrderMailer < ApplicationMailer
  # What the quote mail reads for each task, loaded with the order.
  QUOTE_MAIL_TASK_ASSOCIATIONS = [
    { job_service: :job_service_group },
    { job_task_quote: :job_task_quote_options },
    { job_task_options: :job_option }
  ].freeze

  # The mails to staff and the customer are written in the recipient's saved language (see ApplicationMailer#mail);
  # the quote, the decision confirmation and the staff assignment carry a French and an English half for everyone.
  # Subjects come from job_order_mailer.<action>.
  def send_job_submitted(job_order_id)
    return unless JobOrder.where(id: job_order_id).present?
    @job_order = JobOrder.find(job_order_id)

    staff_mail("makerspace@uottawa.ca")
  end

  # an order went back to "Waiting for Staff Approval" because its quote no longer describes it
  # (JobOrder#apply_owner_change!, JobOrder#checkout_link). Same recipient and expedited handling as send_job_submitted.
  def send_job_requote_needed(job_order_id, reason)
    return unless JobOrder.exists?(id: job_order_id)
    @job_order = JobOrder.find(job_order_id)
    @reason = reason

    staff_mail("makerspace@uottawa.ca", id: @job_order.id)
  end

  # user_comments: the note staff wrote for the customer with the quote, shown in the mail when present.
  def send_job_quote(job_order_id, reminder = false, user_comments = nil)
    return unless JobOrder.exists?(id: job_order_id)
    @job_order = JobOrder.includes(job_tasks: QUOTE_MAIL_TASK_ASSOCIATIONS).find(job_order_id)
    @user_comments = user_comments.presence

    @reminder = reminder
    @hash = @job_order.approval_token

    approved_before = @job_order.job_order_statuses.where(job_status: JobStatus.user_approval).count > 1
    customer_mail(bilingual_subject(approved_before ? "subject_reapproved" : "subject_approved", id: @job_order.id))
  end

  def send_job_declined(job_order_id)
    return unless JobOrder.where(id: job_order_id).present?
    @job_order = JobOrder.find(job_order_id)

    customer_mail(subject_for(@job_order.user.email, id: @job_order.id))
  end

  def send_job_user_approval(job_order_id)
    return unless JobOrder.where(id: job_order_id).present?
    @job_order = JobOrder.find(job_order_id)

    staff_mail("makerspace@uottawa.ca")
  end

  def send_job_user_declined(job_order_id)
    return unless JobOrder.where(id: job_order_id).present?
    @job_order = JobOrder.find(job_order_id)

    staff_mail("makerspace@uottawa.ca")
  end

  # Tells the customer their own approval or decline of the quote was recorded.
  def send_job_decision_confirmation(job_order_id, approved)
    return unless JobOrder.where(id: job_order_id).present?
    @job_order = JobOrder.find(job_order_id)
    @approved = approved

    customer_mail(bilingual_subject(approved ? "subject_approved" : "subject_declined", id: @job_order.id))
  end

  def send_job_completed(job_order_id, message)
    return unless JobOrder.where(id: job_order_id).present?
    @job_order = JobOrder.find(job_order_id)

    @message =
      if message.present?
        sanitize(message)
      else
        sanitize(JobOrderMessage
          .find_by(name: "processed")
          .retrieve_message(@job_order.id))
      end

    customer_mail(subject_for(@job_order.user.email, id: @job_order.id))
  end

  def payment_succeeded(job_order_id, message = nil)
    return unless JobOrder.where(id: job_order_id).present?
    @job_order = JobOrder.find(job_order_id)
    @message = sanitize(message) if message.present?

    customer_mail(subject_for(@job_order.user.email, id: @job_order.id))
  end

  def staff_assigned(job_order_id, staff_member_id)
    return if JobOrder.where(id: job_order_id).blank?
    @job_order = JobOrder.find(job_order_id)

    @staff_member = User.find(staff_member_id)

    staff_mail(@staff_member.email, id: @job_order.id)
  end

  private

  def customer_mail(subject)
    mail(to: @job_order.user.email, reply_to: "makerspace@uottawa.ca", bcc: "uottawa.makerepo@gmail.com", subject:)
  end

  # An expedited order is flagged in the subject and sent with high priority.
  def staff_mail(address, **values)
    subject = subject_for(address, **values)
    return mail(to: address, subject:) unless @job_order.expedited?

    subject = I18n.t("job_order_mailer.expedited_subject", subject:, locale: recipient_locale(address))
    mail(to: address, subject:, Importance: "high", "X-Priority": "1")
  end
end
