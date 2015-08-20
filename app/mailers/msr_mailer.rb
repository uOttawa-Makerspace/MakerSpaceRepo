class MsrMailer < ApplicationMailer

  def repo_report(repository)
  	@repository = repository
  	mail(:to => 'meneliktucker@hotmail.com', :subject => "Repository #{repository.title} reported")
  end

  def reset_password_email email, newpassword
  	@user = User.find_by email: email
  	@password = newpassword
  	mail(to: email, subject: "New password for MakerRepo")
  end

end
