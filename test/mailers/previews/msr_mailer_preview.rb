# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/msr_mailer
class MsrMailerPreview < ActionMailer::Preview
  def confirmation_email
    MsrMailer.confirmation_email(User.first, "sample_confirmation_hash")
  end

  def email_confirmation_email
    MsrMailer.email_confirmation_email(
      "new_email@example.com",
      User.first,
      "sample_user_hash",
      "sample_email_hash"
    )
  end

  def email_changed_email
    MsrMailer.email_changed_email(User.first, "old_email@example.com")
  end

  def confirm_password_change
    MsrMailer.confirm_password_change(User.first)
  end

  def welcome_email
    MsrMailer.welcome_email(User.first)
  end

  def send_profile_update
    MsrMailer.send_profile_update(["user1@example.com", "user2@example.com"])
  end

  def send_cc_money_email
    MsrMailer.send_cc_money_email(
      "user@example.com",
      100,
      "sample_cc_hash"
    )
  end

  def send_kit_email
    user = User.first
    pp = ProficientProject.first || OpenStruct.new(id: 1, title: "Sample Project")
    MsrMailer.send_kit_email(user, pp)
  end

  def send_print_user_approval_to_makerspace
    print_order = PrintOrder.first
    MsrMailer.send_print_user_approval_to_makerspace(print_order&.id || 1)
  end

  def send_print_to_makerspace
    print_order = PrintOrder.first
    MsrMailer.send_print_to_makerspace(print_order&.id || 1)
  end

  def send_print_quote
    user = User.new(name: "Test Name", email: "test@makerepo.com")
    print_order = PrintOrder.first || PrintOrder.new(
      file_file_name: "file_name.stl",
      service_charge: 15,
      order_type: 0,
      grams: 350,
      price_per_gram: 0.4,
      expedited: true,
      quote: 44
    )
    MsrMailer.send_print_quote(
      15,                    # expedited_price
      user,
      print_order,
      "Staff comments",      # comments
      5,                     # clean_part_price
      false                  # resend
    )
  end

  def send_print_reminder
    MsrMailer.send_print_reminder("user@example.com", 123)
  end

  def send_print_declined
    MsrMailer.send_print_declined(
      User.new(name: "Test Name", email: "test@makerepo.com"),
      "Staff comments explaining why the print was declined",
      "file_name.stl"
    )
  end

  def send_print_finished
    MsrMailer.send_print_finished(
      User.new(name: "Test Name", email: "test@makerepo.com"),
      "PICKUP-123",          # pickup_id
      10.50,                 # quote
      "Your print is ready for pickup at the Makerspace."  # message
    )
  end

  def send_invoice
    print_order = PrintOrder.first || PrintOrder.new(id: 123)
    MsrMailer.send_invoice("Test User", print_order)
  end

  def send_admin_pp_evaluation
    pp = ProficientProject.first || OpenStruct.new(
      id: 1,
      title: "Sample Project",
      training: OpenStruct.new(skill: OpenStruct.new(name: "Technical"))
    )
    MsrMailer.send_admin_pp_evaluation(pp)
  end

  def send_user_pp_evaluation
    user = User.first
    pp = ProficientProject.first || OpenStruct.new(
      id: 1,
      title: "Sample Project",
      training: OpenStruct.new(skill: OpenStruct.new(name: "Technical"))
    )
    MsrMailer.send_user_pp_evaluation(pp, user)
  end

  def send_results_pp
    user = User.first
    pp = ProficientProject.first || OpenStruct.new(id: 1, title: "Sample Project")
    oi = OpenStruct.new(
      id: 1,
      proficient_project: pp,
      status: "passed"
    )
    MsrMailer.send_results_pp(oi, user, "passed")
  end

  def repository_email
    MsrMailer.repo_report(Repository.first, User.first)
  end

  def forgot_password_email
    MsrMailer.forgot_password(
      User.first.email,
      "sample_user_hash",
      "sample_expiry_date_hash"
    )
  end

  def send_inactive_email
    MsrMailer.send_inactive_email(User.first)
  end

  def send_training_report
    MsrMailer.send_training_report(["admin@example.com"])
  end

  def send_monthly_report
    MsrMailer.send_monthly_report(["admin@example.com"])
  end

  def send_weekly_report
    MsrMailer.send_weekly_report(["admin@example.com"])
  end

  def send_cdel_monthly_report
    MsrMailer.send_cdel_monthly_report("cdel@example.com")
  end

  def print_failed
    user = User.first
    printer = Printer.first || OpenStruct.new(id: 1, number: "Printer-01")
    MsrMailer.print_failed(
      printer,
      user,
      "The printer ran out of filament. Please come restart your print."
    )
  end

  def waiver_reminder_email
    MsrMailer.waiver_reminder_email("no_waiver_user@gmail.com")
  end

  def issue_email
    MsrMailer.issue_email(
      "Julia",
      "julia@gmail.com",
      "issue",
      "photo upload not working",
      "0xDEADBEEF"  # app_version
    )
  end

  def send_exam
    user = User.first
    training_session = TrainingSession.first || OpenStruct.new(
      id: 1,
      training: OpenStruct.new(name: "3D Printing Basics")
    )
    MsrMailer.send_exam(user, training_session)
  end

  def finishing_exam
    user = User.first
    training_session = TrainingSession.first || OpenStruct.new(
      id: 1,
      training: OpenStruct.new(name: "3D Printing Basics")
    )
    exam = Exam.first || OpenStruct.new(
      id: 1,
      training_session: training_session,
      score: 85
    )
    MsrMailer.finishing_exam(user, exam)
  end

  def exam_results_staff
    user = User.first
    staff = User.where(role: "staff").first || User.first
    training_session = TrainingSession.first || OpenStruct.new(
      id: 1,
      training: OpenStruct.new(name: "3D Printing Basics"),
      user: staff
    )
    exam = Exam.first || OpenStruct.new(
      id: 1,
      training_session: training_session,
      score: 85
    )
    MsrMailer.exam_results_staff(user, exam)
  end

  def send_new_project_proposals
    MsrMailer.send_new_project_proposals
  end

  def send_notification_to_staff_for_joining_task
    volunteer_task = VolunteerTask.first
    volunteer = User.first
    staff = User.where(role: "staff").first

    MsrMailer.send_notification_to_staff_for_joining_task(
      volunteer_task&.id || 1,
      volunteer.id,
      staff&.id
    )
  end

  def send_notification_to_volunteer_for_joining_task
    volunteer_task = VolunteerTask.first
    volunteer = User.first
    staff = User.where(role: "staff").first

    MsrMailer.send_notification_to_volunteer_for_joining_task(
      volunteer_task&.id || 1,
      volunteer.id,
      staff&.id
    )
  end

  def send_notification_for_task_request
    volunteer_task = VolunteerTask.first
    volunteer = User.first

    MsrMailer.send_notification_for_task_request(
      volunteer_task&.id || 1,
      volunteer.id
    )
  end

  def send_notification_for_task_request_update
    volunteer_task_request = VolunteerTaskRequest.first
    MsrMailer.send_notification_for_task_request_update(
      volunteer_task_request&.id || 1
    )
  end

  def send_email_for_stripe_transfer
    MsrMailer.send_email_for_stripe_transfer(
      "tr_1234567890",           # transfer_id
      Date.today.to_s,           # date
      50000,                     # amount in cents ($500.00)
      "TD Bank",                 # bank
      "12345"                    # routing_number
    )
  end

  def unlock_account
    MsrMailer.unlock_account(User.first, "sample_unlock_hash")
  end
end