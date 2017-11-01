class MsrMailer < ApplicationMailer

	def welcome_email(user)
		@user = user
		@url  = 'http://makerepo.com/login'
		mail(to: @user.email, subject: "Welcome to MakerRepo")
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

	def send_training_report(email1, csv1, csv2)
		attachments['MakerspaceTraining.csv'] = {mime_type: 'text/csv', content: csv1}
		attachments['MtcTraining.csv'] = {mime_type: 'text/csv', content: csv2}

		mail(to: email1, subject: 'Training Reports')
	end


	#test
	def send_monthly_report(email1, csv1, csv2, csv3, csv4, csv5, csv6, csv7)
		attachments['NewUsers.csv'] = {mime_type: 'text/csv', content: csv1}
		attachments['TotalVisits.csv'] = {mime_type: 'text/csv', content: csv2}
		attachments['UniqueVisits.csv'] = {mime_type: 'text/csv', content: csv3}
		attachments['FacultyFrequency.csv'] = {mime_type: 'text/csv', content: csv4}
		attachments['GenderFrequency.csv'] = {mime_type: 'text/csv', content: csv5}
		attachments['MakerspaceTraining'] = {mime_type: 'text/csv', content: csv6}
		attachments['MtcTraining'] = {mime_type: 'text/csv', content: csv7}

		mail(to: email1, subject: 'Monthly Reports')
	end
		#test
		def send_weekly_report(email1, csv1, csv2, csv3, csv4, csv5, csv6, csv7)
			attachments['NewUsers.csv'] = {mime_type: 'text/csv', content: csv1}
			attachments['TotalVisits.csv'] = {mime_type: 'text/csv', content: csv2}
			attachments['UniqueVisits.csv'] = {mime_type: 'text/csv', content: csv3}
			attachments['FacultyFrequency.csv'] = {mime_type: 'text/csv', content: csv4}
			attachments['GenderFrequency.csv'] = {mime_type: 'text/csv', content: csv5}
			attachments['MakerspaceTraining'] = {mime_type: 'text/csv', content: csv6}
			attachments['MtcTraining'] = {mime_type: 'text/csv', content: csv7}

			mail(to: email1, subject: 'Weekly Reports')
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
end
