# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/job_order_mailer
class JobOrderMailerPreview < ActionMailer::Preview
  def send_job_submitted
    job_order = JobOrder.last || JobOrder.create!(user: User.last, expedited: true)
    JobOrderMailer.send_job_submitted(job_order.id)
  end

  def send_job_quote
    job_order = JobOrder.last || create_job_order_with_statuses
    JobOrderMailer.send_job_quote(JobOrder.find(454).id)
  end

  def send_job_quote_reminder
    job_order = JobOrder.last || create_job_order_with_statuses
    JobOrderMailer.send_job_quote(job_order.id, true)
  end

  def send_job_declined
    job_order = JobOrder.last || create_job_order_with_files
    JobOrderMailer.send_job_declined(job_order.id)
  end

  def send_job_user_approval
    job_order = JobOrder.last || JobOrder.create!(user: User.last, expedited: false)
    JobOrderMailer.send_job_user_approval(job_order.id)
  end

  def send_job_completed
    job_order = JobOrder.last || create_job_order_with_files
    JobOrderMailer.send_job_completed(job_order.id, "Your items are ready for pickup at the front desk.")
  end

  def send_job_completed_with_default_message
    job_order = JobOrder.last || create_job_order_with_files
    JobOrderMailer.send_job_completed(job_order.id, nil)
  end

  def payment_succeeded
    job_order = JobOrder.last || create_job_order_with_files
    JobOrderMailer.payment_succeeded(job_order.id)
  end

  def payment_failed
    job_order = JobOrder.last || create_job_order_with_files
    JobOrderMailer.payment_failed(job_order.id)
  end

  def staff_assigned
    job_order = JobOrder.last || JobOrder.create!(user: User.last, expedited: true)
    staff_member = User.staff.first || User.create!(email: 'staff@example.com', role: 'staff')
    JobOrderMailer.staff_assigned(job_order.id, staff_member.id)
  end

  private

  def create_job_order_with_statuses
    JobOrder.create!(
      user: User.last || User.create!(email: 'user@example.com'),
      job_order_statuses: [
        JobOrderStatus.new(job_status: JobStatus::USER_APPROVAL),
        JobOrderStatus.new(job_status: JobStatus::USER_APPROVAL) # For testing re-approved scenario
      ]
    )
  end

  def create_job_order_with_files
    JobOrder.create!(
      user: User.last || User.create!(email: 'user@example.com'),
      user_files: [UserFile.new(filename: 'test.stl', file: fixture_file_upload('test.stl'))]
    )
  end
end