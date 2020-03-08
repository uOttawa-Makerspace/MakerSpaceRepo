class MsrMailer < ApplicationMailer

	def welcome_email(user)
		@user = user
		@url  = 'http://makerepo.com/login'
		mail(to: @user.email, subject: "Welcome to MakerRepo")
	end

	def send_survey
		all_users = User.active.pluck(:email)
		mail(to: 'bruno.mrlima@gmail.com', subject: 'Richard L\'Abbé Makerspace Survey 2019', bcc: all_users)
	end

	def send_print_user_approval_to_makerspace(id)
		mail(to: "makerspace@uottawa.ca", subject: 'Print Order has been accepted by user on Makerepo | Print ID : '+id.to_s)
	end

	def send_print_to_makerspace(id)
		mail(to: "makerspace@uottawa.ca", subject: 'Print Order has been submitted on Makerepo | Print ID : '+id.to_s)
	end

	def send_print_quote(expedited_price, user, print_order, comments)
		@expedited_price = expedited_price
	  @user = user
	  @print_order = print_order
		@comments = comments
		mail(to: @user.email, subject: 'Print Request Approval : ' + @print_order.file_file_name)
	end

	def send_print_disapproval(user, comments, filename)
		@user = user
		@comments = comments
		mail(to: @user.email, subject: 'Print Request Disapproval : '+filename)
	end

	def send_print_finished(user, filename, pickup_id)
		@user = user
    @pickup_id = pickup_id
		mail(to: @user.email, subject: 'Your print : '+ filename +' is ready !')
  end

  def send_invoice(name, quote, number, order_type)
    @name = name
    @quote = quote
    @number = number
		if order_type != 1
			@order_type = "3D Printed Part"
		else
			@order_type = "Laser Cut/Engraving"
		end
    mail(to: "uomakerspaceprintinvoices@gmail.com", subject: 'Invoice for Order #' + @number.to_s + ' ')
  end

	def send_ommic
		all_users = User.where("email like ? and length(email) = 19", "%@uottawa.ca").pluck(:email).uniq
		attachments['ommic1.png'] = File.read("#{Rails.root}/app/assets/images/mail/ommic1.png")
		attachments['ommic2.jpg'] = File.read("#{Rails.root}/app/assets/images/mail/ommic2.jpg")
		attachments['ommic1.jpg'] = File.read("#{Rails.root}/app/assets/images/mail/ommic3.jpg")
		mail(to: 'bruno.mrlima@gmail.com', subject: 'OMMIC Conference | Discount for students', bcc: all_users)
	end

	def repo_report(repository)
		@repository = repository
		mail(:to => 'uottawa.makerepo@gmail.com', :subject => "Repository #{repository.title} reported")
	end

	def reset_password_email (email, newpassword)
		@user = User.find_by email: email
		@password = newpassword
		mail(to: email, subject: "New password for MakerRepo")
	end

	def send_training_report(to)
		attachments['MakerspaceTraining.csv'] = { mime_type: 'text/csv', content: ReportGenerator.makerspace_training_report }
		attachments['MtcTraining.csv'] = { mime_type: 'text/csv', content: ReportGenerator.mtc_training_report }

		mail(to: "makerspace@uottawa.ca", subject: 'Training Reports', bcc: to)
	end

	# @param [Array<String>] to
	def send_monthly_report(to)
		start_date = 1.month.ago.beginning_of_month
		end_date = 1.month.ago.end_of_month

		attachments['NewMakerRepoUsers.csv'] = { mime_type: 'application/xlsx', content: ReportGenerator.generate_new_users_report(start_date, end_date).to_stream }
		attachments['Visitors.xlsx'] = { mime_type: 'application/xlsx', content: ReportGenerator.generate_visitors_report(start_date, end_date).to_stream }
		attachments['FacultyFrequency.csv'] = { mime_type: 'text/csv', content: ReportGenerator.faculty_frequency_report(start_date, end_date) }
		attachments['GenderFrequency.csv'] = { mime_type: 'text/csv', content: ReportGenerator.gender_frequency_report(start_date, end_date) }
		attachments['MakerspaceTrainings.csv'] = { mime_type: 'text/csv', content: ReportGenerator.makerspace_training_report(start_date, end_date) }
		attachments['MtcTrainings.csv'] = { mime_type: 'text/csv', content: ReportGenerator.mtc_training_report(start_date, end_date) }

		mail(to: "makerspace@uottawa.ca", subject: 'Monthly Reports', bcc: to)
	end

	# @param [Array<String>] to
	def send_weekly_report(to)
		start_date = 1.week.ago.beginning_of_week
		end_date = 1.week.ago.end_of_week

		attachments['NewMakerRepoUsers.csv'] = { mime_type: 'application/xlsx', content: ReportGenerator.generate_new_users_report(start_date, end_date).to_stream }
		attachments['Visitors.xlsx'] = { mime_type: 'application/xlsx', content: ReportGenerator.generate_visitors_report(start_date, end_date).to_stream }
		attachments['FacultyFrequency.csv'] = { mime_type: 'text/csv', content: ReportGenerator.faculty_frequency_report }
		attachments['GenderFrequency.csv'] = { mime_type: 'text/csv', content: ReportGenerator.gender_frequency_report }
		attachments['MakerspaceTrainings.csv'] = { mime_type: 'text/csv', content: ReportGenerator.makerspace_training_report }
		attachments['MtcTrainings.csv'] = { mime_type: 'text/csv', content: ReportGenerator.mtc_training_report }

		mail(to: 'makerspace@uottawa.ca', subject: 'Weekly Reports', bcc: to)
	end

	def send_checklist_reminder(email, master_email)
		@email = email
		mail(to: email, subject: 'Checklist Reminder', bcc: master_email)
	end

	def waiver_reminder_email(email)
    mail(to: email, subject: "Please Sign The Release Agreement!")
  end

	def issue_email(name, email, subject, comments)
		@name = name
		@email = email
		@subject = subject
		@comments = comments

		mail(to: "webmaster@makerepo.com", subject: "Issue Report")
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
		mail(to: email, subject: "New Project Proposal")
	end
end
