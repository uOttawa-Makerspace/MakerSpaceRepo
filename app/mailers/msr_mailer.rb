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

#should test this method
	def send_report(email, csv1, csv2, csv3, csv4, csv5)
	    attachments['NewUsers.csv'] = {mime_type: 'text/csv', content: csv1}
			attachments['Visits.csv'] = {mime_type: 'text/csv', content: csv2}
			attachments['FacultyFrequency.csv'] = {mime_type: 'text/csv', content: csv3}
			attachments['GenderFrequency.csv'] = {mime_type: 'text/csv', content: csv4}
			attachments['UniqueVisitors.csv'] = {mime_type: 'text/csv', content: csv5}

	    mail(to: email, subject: 'Monthly Report')
	end
end
