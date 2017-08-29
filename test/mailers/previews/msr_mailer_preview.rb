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

	def send_report_email
		MsrMailer.send_report('makerspace@uottawa.ca', ReportGenerator.new_user_report,
													ReportGenerator.lab_session_report,
													ReportGenerator.faculty_frequency_report)
	end

	def tac_reminder_email
		MsrMailer.tac_reminder_email('baduser@tac.com')
	end

	def issue_email
		MsrMailer.issue_email("Julia", "julia@gmail.com", "issue", "photo upload not working")
	end
end
