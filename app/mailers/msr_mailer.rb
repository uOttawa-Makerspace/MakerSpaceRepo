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
		mail(to: @user.email, reply_to: "makerspace@uottawa.ca", cc: "uottawa.makerepo@gmail.com", subject: 'Print Request Approval : ' + @print_order.file_file_name)
	end

	def send_print_disapproval(user, comments, filename)
		@user = user
		@comments = comments
		mail(to: @user.email, reply_to: "makerspace@uottawa.ca", cc: "uottawa.makerepo@gmail.com", subject: 'Print Request Disapproval : '+filename)
	end

	def send_print_finished(user, filename, pickup_id)
		@user = user
    @pickup_id = pickup_id
		mail(to: @user.email, reply_to: "makerspace@uottawa.ca", cc: "uottawa.makerepo@gmail.com", subject: 'Your print : '+ filename +' is ready !')
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

	# def send_report(email, email2, csv1, csv2, csv3, csv4, csv5)
	#     attachments['NewUsers.csv'] = {mime_type: 'text/csv', content: csv1}
	# 		attachments['Visits.csv'] = {mime_type: 'text/csv', content: csv2}
	# 		attachments['FacultyFrequency.csv'] = {mime_type: 'text/csv', content: csv3}
	# 		attachments['GenderFrequency.csv'] = {mime_type: 'text/csv', content: csv4}
	# 		attachments['UniqueVisitors.csv'] = {mime_type: 'text/csv', content: csv5}
	#
	#     mail(to: email, subject: 'Weekly Report', bcc: [email2])
	# end

	# def send_training_report(email1, email2, email3, email4, csv)
	# 	attachments['MakerspaceTraining.csv'] = {mime_type: 'text/csv', content: csv}
	#
	# 	mail(to: email1, subject: 'Weekly Report of Trainings', bcc: [email2, email3, email4])
	# end

	def send_training_report(email1, email2, email3, email4, email5, csv1, csv2)
		attachments['MakerspaceTraining.csv'] = {mime_type: 'text/csv', content: csv1}
		attachments['MtcTraining.csv'] = {mime_type: 'text/csv', content: csv2}

		mail(to: email1, subject: 'Training Reports', bcc: [email2, email3, email4, email5])
	end



	def send_monthly_report(email1, email2, email3, csv1, csv2, csv3, csv4, csv5, csv6, csv7)
		attachments['NewMakerepoUsers.csv'] = {mime_type: 'text/csv', content: csv1}
		attachments['UniqueVisits.csv'] = {mime_type: 'text/csv', content: csv2}
		attachments['TotalVisits.csv'] = {mime_type: 'text/csv', content: csv3}
		attachments['FacultyFrequency.csv'] = {mime_type: 'text/csv', content: csv4}
		attachments['GenderFrequency.csv'] = {mime_type: 'text/csv', content: csv5}
		attachments['MakerspaceTrainings.csv'] = {mime_type: 'text/csv', content: csv6}
		attachments['MtcTrainings.csv'] = {mime_type: 'text/csv', content: csv7}

		mail(to: email1, subject: 'Monthly Reports', bcc: [email2, email3])
	end

	def send_weekly_report(email1, email2, email3, csv1, csv2, csv3, csv4, csv5, csv6, csv7)
		attachments['NewMakerepoUsers.csv'] = {mime_type: 'text/csv', content: csv1}
		attachments['UniqueVisits.csv'] = {mime_type: 'text/csv', content: csv2}
		attachments['TotalVisits.csv'] = {mime_type: 'text/csv', content: csv3}
		attachments['FacultyFrequency.csv'] = {mime_type: 'text/csv', content: csv4}
		attachments['GenderFrequency.csv'] = {mime_type: 'text/csv', content: csv5}
		attachments['MakerspaceTrainings.csv'] = {mime_type: 'text/csv', content: csv6}
		attachments['MtcTrainings.csv'] = {mime_type: 'text/csv', content: csv7}

		mail(to: email1, subject: 'Weekly Reports', bcc: [email2, email3])
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
