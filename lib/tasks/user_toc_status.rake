namespace :user_toc_status do

  desc "query the db for users who haven't signed the terms of service
        or it's been a year since they did so."
  task check_status_task: :environment do

  end

  desc "email those users with a link to sign it again"
  task email_users_task: :environment do
    
  end

end
