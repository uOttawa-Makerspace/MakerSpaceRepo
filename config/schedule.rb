every '0 7 1 * *' do #At 7am on 1st day of every month
  runner "MsrMailer.send_report('makerspace@uottawa.ca', 
            ReportGenerator.new_user_report,
  				  ReportGenerator.lab_session_report,
  				  ReportGenerator.faculty_frequency_report, ReportGenerator.gender_frequesncy_report,
            ReportGenerator.unique_visitors_report).deliver_now"
end

every '0 7 * * 0' do #At 7am of first day of every week
  runner "MsrMailer.send_training_report('brunsfield@uottawa.ca', 'MTC@uottawa.ca', 'makerspace@uottawa.ca',
                                        'ReportGenerator.training_report(1.week.ago.beginning_of_week, 1.week.ago.end_of_week)').deliver_now"
end



# Use this file to easily define all of your cron jobs.
#
# It's helpful, but not entirely necessary to understand cron before proceeding.
# http://en.wikipedia.org/wiki/Cron

# Example:
#
# set :output, "/path/to/my/cron_log.log"
#
# every 2.hours do
#   command "/usr/bin/some_great_command"
#   runner "MyModel.some_method"
#   rake "some:great:rake:task"
# end
#
# every 4.days do
#   runner "AnotherModel.prune_old_records"
# end

# Learn more: http://github.com/javan/whenever
