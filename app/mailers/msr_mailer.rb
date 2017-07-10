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
	def send_report(email, csv1, csv2, csv3)
	    attachments['Report1.csv'] = {mime_type: 'text/csv', content: csv1}
			attachments['Report2.csv'] = {mime_type: 'text/csv', content: csv2}
			attachments['Report3.csv'] = {mime_type: 'text/csv', content: csv3}

	    mail(to: email, subject: 'Monthly Report')
	end
end
