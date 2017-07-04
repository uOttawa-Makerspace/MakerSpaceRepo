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
		assert email.body.to_s.include? "Bob"
		assert email.body.to_s.include? "Password2"
	end

	test "Sending reports" do
		email = MsrMailer.send_report('makerspace@uottawa.ca', Admin::ReportGeneratorController.new.report1_generator(),
																	Admin::ReportGeneratorController.new.report2_generator(),
																	Admin::ReportGeneratorController.new.report3_generator())

		assert_equal ['uottawa.makerepo@gmail.com'], email.from
		assert_equal ['makerspace@uottawa.ca'], email.to
		assert_equal 'Monthly Report', email.subject
		assert_not_nil(email.attachments, "No attachments found")
	end
end
