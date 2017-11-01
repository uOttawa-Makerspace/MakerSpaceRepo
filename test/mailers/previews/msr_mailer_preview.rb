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

	def send_monthly_report
		MsrMailer.send_monthly_report('abc@gmail.com', ReportGenerator.new_user_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month),
							ReportGenerator.unique_visitors_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month),
							ReportGenerator.lab_session_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month),
							ReportGenerator.faculty_frequency_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month),
							ReportGenerator.gender_frequency_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month),
							ReportGenerator.makerspace_training_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month),
							ReportGenerator.mtc_training_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month))
	end

	def send_weekly_report
		MsrMailer.send_weekly_report('abc@gmail.com', ReportGenerator.new_user_report,
						ReportGenerator.unique_visitors_report,
						ReportGenerator.lab_session_report,
						ReportGenerator.faculty_frequency_report,
						ReportGenerator.gender_frequency_report,
						ReportGenerator.makerspace_training_report,
						ReportGenerator.mtc_training_report)
	end

	def send_training_report
		MsrMailer.send_training_report('abc@gmail.com',ReportGenerator.makerspace_training_report, ReportGenerator.mtc_training_report)
	end
	
	def waiver_reminder_email
		MsrMailer.waiver_reminder_email('no_waiver_user@gmail.com')
	end

	def issue_email
		MsrMailer.issue_email("Julia", "julia@gmail.com", "issue", "photo upload not working")
	end
end
