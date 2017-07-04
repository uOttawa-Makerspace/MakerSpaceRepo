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
		MsrMailer.send_report('makerspace@uottawa.ca', Admin::ReportGeneratorController.new.report1_generator(),
													Admin::ReportGeneratorController.new.report2_generator(),
													Admin::ReportGeneratorController.new.report3_generator())
	end

end
