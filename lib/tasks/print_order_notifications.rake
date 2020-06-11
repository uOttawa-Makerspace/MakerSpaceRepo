namespace :print_order_notifications do
  desc "Sends email reminders to users that didn't give an answer to their print order after 2 weeks"
  task :two_weeks_reminder => :environment do
    PrintOrder.where(approved: true, user_approval: nil, printed: nil).each do |print_remind|
      if (print_remind.updated_at.to_date..Time.now.to_date).count == 14
          MsrMailer.send_print_reminder(print_remind.user.email, print_remind.id).deliver_now
      end
    end
  end
end

