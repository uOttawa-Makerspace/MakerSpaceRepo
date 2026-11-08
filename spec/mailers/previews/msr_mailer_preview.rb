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
      "sample_email_change_token"
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
      "sample_reset_token"
    )
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

  def unlock_account
    MsrMailer.unlock_account(User.first, "sample_unlock_hash")
  end

  def new_printer_issue
    printer = Printer.first || OpenStruct.new(
      id: 1,
      name: "Prusa MK3S #1",
      number: "PR-001"
    )
    
    reporter = User.first || OpenStruct.new(
      id: 1,
      name: "John Doe",
      email: "john.doe@uottawa.ca"
    )
    
    issue = PrinterIssue.first || OpenStruct.new(
      id: 42,
      printer: printer,
      reporter: reporter,
      summary: "Extruder jamming during print",
      description: "The extruder keeps jamming about 2 hours into prints. May need to clean the nozzle or check the filament path.",
      active: true,
      created_at: Time.current,
      updated_at: Time.current
    )
    
    MsrMailer.new_printer_issue(issue, "makerspace@uottawa.ca")
  end
end