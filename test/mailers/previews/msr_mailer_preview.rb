# Preview all emails at http://localhost:3000/rails/mailers/msr_mailer
class MsrMailerPreview < ActionMailer::Preview

	def welcome_email
		MsrMailer.welcome_email(User.first)
	end

	def repository_email
		MsrMailer.repo_report(Repository.first)
	end

	def reset_password_email
		MsrMailer.reset_password_email(User.first.email , "Password2")
	end
end
