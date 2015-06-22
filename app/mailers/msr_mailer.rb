class MsrMailer < ApplicationMailer

  def repo_report(repository)
  	@repository = repository
  	mail(:to => 'meneliktucker@hotmail.com', :subject => "Repository #{repository.title} reported")
  end

end
