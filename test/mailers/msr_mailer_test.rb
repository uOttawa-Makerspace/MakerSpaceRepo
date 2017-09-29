require 'test_helper'

class MsrMailerTest < ActionMailer::TestCase
	test "Welcome email" do
		user = users(:bob)
		email = MsrMailer.welcome_email(user)

		assert_equal ['uottawa.makerepo@gmail.com'], email.from
		assert_equal ['bob@gmail.com'], email.to
		assert_equal 'Welcome to MakerRepo', email.subject
		assert email.body.to_s.include? "Bob"
		assert email.body.to_s.include? "bob"
		assert email.body.to_s.include? "http://makerepo.com/login"
	end

	test "Repository email" do
		repository = repositories(:one)
		email = MsrMailer.repo_report(repository)

		assert_equal ['uottawa.makerepo@gmail.com'], email.from
		assert_equal ['uottawa.makerepo@gmail.com'], email.to
		assert_equal 'Repository Repository1 reported', email.subject
	end

	test "Reset password email" do
		user = users(:bob)
		newpassword = "Password2"
		email = MsrMailer.reset_password_email user.email, newpassword

		assert_equal ['uottawa.makerepo@gmail.com'], email.from
		assert_equal ['bob@gmail.com'], email.to
		assert_equal 'New password for MakerRepo', email.subject
		assert email.body.to_s.include? "bob"
		assert email.body.to_s.include? "Password2"
	end

	test "Sending reports" do
		email = MsrMailer.send_report('makerspace@uottawa.ca', 'hanis@uottawa.ca', ReportGenerator.new_user_report,
						ReportGenerator.lab_session_report,
						ReportGenerator.faculty_frequency_report, ReportGenerator.gender_frequesncy_report, ReportGenerator.unique_visitors_report)

		assert_equal ['uottawa.makerepo@gmail.com'], email.from
		assert_equal ['makerspace@uottawa.ca'], email.to
		assert_equal ['hanis@uottawa.ca'], email.bcc
		assert_equal 'Weekly Report', email.subject
		assert_not_nil(email.attachments, "No attachments found")
	end


	test "Sending training reports" do
		email = MsrMailer.send_training_report('brunsfield@uottawa.ca', 'MTC@uottawa.ca', 'makerspace@uottawa.ca', 'hanis@uottawa.ca',
																						ReportGenerator.training_report())
		assert_equal ['uottawa.makerepo@gmail.com'], email.from
		assert_equal ['brunsfield@uottawa.ca'], email.to
		assert_equal ['MTC@uottawa.ca', 'makerspace@uottawa.ca', 'hanis@uottawa.ca'], email.bcc
		assert_not_nil(email.attachments, "No attachments found")
	end

  test "Send waiver reminder email" do
		email = MsrMailer.waiver_reminder_email('abc@123.com')
		assert_equal ['uottawa.makerepo@gmail.com'], email.from
		assert_equal ['abc@123.com'], email.to
		assert_equal 'Please Sign The Release Agreement!', email.subject

	end

	test "issue emails get sent successfully" do
		email = MsrMailer.issue_email("Julia", "julia@gmail.com", "issue", "photo upload not working")
		assert_equal ['webmaster@makerepo.com'], email.to
		assert email.body.to_s.include? "issue"
		assert email.body.to_s.include? "photo upload not working"
		assert email.body.to_s.include? "Julia"
		assert email.body.to_s.include? "julia@gmail.com"
		assert_equal 'Issue Report', email.subject

	end
end
