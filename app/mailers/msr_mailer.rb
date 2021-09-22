# frozen_string_literal: true

class MsrMailer < ApplicationMailer

  def confirmation_email(user, hash)
    @user = user
    @hash = hash
    mail(to: @user.email, subject: 'Makerepo | Please confirm your email')
  end

  def email_confirmation_email(new_email, user, user_hash, email_hash)
    @new_email = new_email
    @user = user
    @email_hash = email_hash
    @user_hash = user_hash
    mail(to: new_email, subject: 'Makerepo | Please confirm your new email')
  end

  def email_changed_email(user, old_email)
    @user = user
    mail(to: old_email, subject: 'Makerepo | Email has changed')
  end

  def confirm_password_change(user)
    @user = user
    mail(to: @user.email, subject: 'MakerRepo | Your password has been changed')
  end

  def welcome_email(user)
    @user = user
    @url  = 'http://makerepo.com/login'
    mail(to: @user.email, subject: 'Welcome to MakerRepo')
  end

  def send_survey
    all_users = User.active.pluck(:email)
    mail(to: 'bruno.mrlima@gmail.com', subject: 'Richard L\'Abbé Makerspace Survey 2019', bcc: all_users)
  end

  def send_profile_update(bcc_emails)
    mail(to: 'uottawa.makerepo@gmail.com', subject: 'CEED - Action Needed - Please update your profile information', bcc: bcc_emails)
  end

  def send_survey_ceed(email)
    mail(to: email, subject: 'Makerspace/Brunsfield Centre Survey - $25 Amazon gift card draw!')
  end

  def send_cc_money_email(email, cc, hash)
    @cc = cc
    @hash = hash
    mail(to: email, subject: 'Your CC Money order')
  end

  def send_kit_email(user, pp)
    @user = user
    @pp = pp
    mail(to: @user.email, subject: 'Your proficient project kit order')
  end

  def send_print_user_approval_to_makerspace(id)
    @print_id = id
    if PrintOrder.find(id).expedited?
      mail(to: 'makerspace@uottawa.ca', subject: 'EXPEDITED: A user has approved a print order', 'Importance': 'high', 'X-Priority': '1')
    else
      mail(to: 'makerspace@uottawa.ca', subject: 'A user has approved a print order')
    end
  end

  def send_print_to_makerspace(id)
    @print_id = id
    if PrintOrder.find(id).expedited?
      mail(to: 'makerspace@uottawa.ca', subject: 'EXPEDITED: A new print order has been submitted', 'Importance': 'high', 'X-Priority': '1')
    else
      mail(to: 'makerspace@uottawa.ca', subject: 'A new print order has been submitted')
    end
  end

  def send_print_quote(expedited_price, user, print_order, comments, clean_part_price, resend)
    @clean_part_price = clean_part_price
    @expedited_price = expedited_price
    @user = user
    @print_order = print_order
    @comments = comments
    @resend = resend
    mail(to: @user.email, reply_to: 'makerspace@uottawa.ca', bcc: 'uottawa.makerepo@gmail.com', subject: "Your print \"#{@print_order.file.filename}\" has been approved!")
  end

  def send_print_reminder(email, id)
    mail(to: email, subject: "Reminder for your print order ##{id}")
  end

  def send_print_declined(user, comments, filename)
    @user = user
    @comments = comments
    mail(to: @user.email, reply_to: 'makerspace@uottawa.ca', bcc: 'uottawa.makerepo@gmail.com', subject: "Your print \"#{filename}\" has been denied")
  end

  def send_print_finished(user, pickup_id, quote, message)
    @quote = quote
    @user = user
    @pickup_id = pickup_id
    @message = message.html_safe
    mail(to: @user.email, reply_to: 'makerspace@uottawa.ca', bcc: 'uottawa.makerepo@gmail.com', subject: 'Your print is available for pickup')
  end

  def send_invoice(name, print_order)
    @name = name
    @print_order = print_order
    mail(to: 'uomakerspaceprintinvoices@gmail.com', subject: 'Invoice for Order #' + @print_order.id.to_s + ' ')
  end

  def send_admin_pp_evaluation(pp)
    @pp = pp
    email = if @pp.training.skill.name.downcase == 'technical'
              'makerspace@uottawa.ca'
            else
              'mtc@uottawa.ca'
            end
    mail(to: email, subject: 'A new proficient project needs to be evaluated')
  end

  def send_user_pp_evaluation(pp, user)
    @pp = pp
    @user = user
    @email = if @pp.training.skill.name.downcase == 'technical'
              'makerspace@uottawa.ca'
            else
              'mtc@uottawa.ca'
            end
    mail(to: @user.email, subject: 'Your Proficient Project Request')
  end

  def send_results_pp(pp, user, result)
    @result = result
    @pp = pp
    @user = user
    mail(to: @user.email, subject: 'Your Proficient Project Results')
  end

  def send_ommic
    all_users = User.where('email like ? and length(email) = 19', '%@uottawa.ca').pluck(:email).uniq
    attachments['ommic1.png'] = File.read("#{Rails.root}/app/assets/images/mail/ommic1.png")
    attachments['ommic2.jpg'] = File.read("#{Rails.root}/app/assets/images/mail/ommic2.jpg")
    attachments['ommic1.jpg'] = File.read("#{Rails.root}/app/assets/images/mail/ommic3.jpg")
    mail(to: 'bruno.mrlima@gmail.com', subject: 'OMMIC Conference | Discount for students', bcc: all_users)
  end

  def repo_report(repository, user)
    @repository = repository
    @user = user
    mail(from: user.email, to: 'uottawa.makerepo@gmail.com', subject: "Repository #{repository.title} reported")
  end

  # THIS IS DEPRECATED
  # def reset_password_email(email, newpassword)
  #   @user = User.find_by email: email
  #   @password = newpassword
  #   mail(to: email, subject: 'New password for MakerRepo')
  # end

  def forgot_password(email, user_hash, expiry_date_hash)
    @user_hash = user_hash
    @expiry_date_hash = expiry_date_hash
    mail(to: email, subject: 'Reset your MakerRepo password')
  end

  def send_inactive_email(user)
    @user = user
    mail(to: @user.email, subject: 'Inactive MakerRepo password')
  end

  def send_training_report(to)
    start_date = 1.week.ago.beginning_of_week
    end_date = 1.week.ago.end_of_week

    attachments['TrainingAttendees.xlsx'] = { mime_type: 'text/xlsx', content: ReportGenerator.generate_training_attendees_report(start_date, end_date).to_stream.read }

    mail(to: 'makerspace@uottawa.ca', subject: 'Training Reports', bcc: to)
  end

  # @param [Array<String>] to
  def send_monthly_report(to)
    start_date = 1.month.ago.beginning_of_month
    end_date = 1.month.ago.end_of_month

    attachments['NewMakerRepoUsers.xlsx'] = { mime_type: 'application/xlsx', content: ReportGenerator.generate_new_users_report(start_date, end_date).to_stream.read }
    attachments['Visitors.xlsx'] = { mime_type: 'application/xlsx', content: ReportGenerator.generate_visitors_report(start_date, end_date).to_stream.read }
    attachments['TrainingAttendees.xlsx'] = { mime_type: 'text/xlsx', content: ReportGenerator.generate_training_attendees_report(start_date, end_date).to_stream.read }

    mail(to: 'makerspace@uottawa.ca', subject: 'Monthly Reports', bcc: to)
  end

  # @param [Array<String>] to
  def send_weekly_report(to)
    start_date = 1.week.ago.beginning_of_week
    end_date = 1.week.ago.end_of_week

    attachments['NewMakerRepoUsers.xlsx'] = { mime_type: 'application/xlsx', content: ReportGenerator.generate_new_users_report(start_date, end_date).to_stream.read }
    attachments['Visitors.xlsx'] = { mime_type: 'application/xlsx', content: ReportGenerator.generate_visitors_report(start_date, end_date).to_stream.read }
    attachments['TrainingAttendees.xlsx'] = { mime_type: 'text/xlsx', content: ReportGenerator.generate_training_attendees_report(start_date, end_date).to_stream.read }

    mail(to: 'makerspace@uottawa.ca', subject: 'Weekly Reports', bcc: to)
  end

  def send_checklist_reminder(email, master_email)
    @email = email
    mail(to: email, subject: 'Checklist Reminder', bcc: master_email)
  end

  def waiver_reminder_email(email)
    mail(to: email, subject: 'Please Sign The Release Agreement!')
  end

  def issue_email(name, email, subject, comments)
    @name = name
    @email = email
    @subject = subject
    @comments = comments

    mail(to: @email, bcc: 'uottawa.makerepo@gmail.com', subject: "Issue Report | #{@subject}")
  end

  def send_exam(user, training_session)
    @user = user
    @training_session = training_session
    email = @user.email
    mail(to: email, subject: 'Exam was sent to you')
  end

  def finishing_exam(user, exam)
    @user = user
    @exam = exam
    @training_session = exam.training_session
    email = @user.email
    mail(to: email, subject: 'You finished your exam')
  end

  def exam_results_staff(user, exam)
    @user = user
    @exam = exam
    @training_session = exam.training_session
    @staff = @training_session.user
    email = @staff.email
    mail(to: email, subject: "#{@user.name.split.first.capitalize} finished an exam")
  end

  def send_new_project_proposals
    email = 'makerlab@uottawa.ca'
    mail(to: email, subject: 'New Project Proposal')
  end

  def send_notification_to_staff_for_joining_task(volunteer_task_id, volunteer_id, staff_id)
    staff = (User.find(staff_id) if staff_id)
    @volunteer_task = VolunteerTask.find(volunteer_task_id)
    @volunteer = User.find(volunteer_id)
    email_staff = if staff
                    staff.email
                  else
                    'volunteer@makerepo.com'
                  end
    mail(to: email_staff, subject: "New join in task: #{@volunteer_task.title.capitalize}")
  end

  def send_notification_to_volunteer_for_joining_task(volunteer_task_id, volunteer_id, staff_id)
    if staff_id
      staff = User.find(staff_id)
      @email_staff = staff.email
    else
      @email_staff = 'volunteer@makerepo.com'
    end
    @volunteer_task = VolunteerTask.find(volunteer_task_id)
    volunteer = User.find(volunteer_id)
    email_volunteer = volunteer.email
    mail(to: email_volunteer, subject: "New join in task: #{@volunteer_task.title.capitalize}")
  end

  def send_notification_for_task_request(volunteer_task_id, volunteer_id)
    @email_staff = 'volunteer@makerepo.com'
    @volunteer_task = VolunteerTask.find(volunteer_task_id)
    volunteer = User.find(volunteer_id)
    email_volunteer = volunteer.email
    mail(to: email_volunteer, subject: "New Request for task: #{@volunteer_task.title.capitalize}", bcc: @email_staff)
  end

  def send_notification_for_task_request_update(volunteer_task_request_id)
    volunteer_task_request = VolunteerTaskRequest.find(volunteer_task_request_id)
    @volunteer_task = volunteer_task_request.volunteer_task
    email_volunteer = volunteer_task_request.user.email
    mail(to: email_volunteer, subject: "Your request was updated: #{@volunteer_task.title.capitalize}")
  end
end
