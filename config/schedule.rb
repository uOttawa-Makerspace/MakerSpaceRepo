# every '0 7 * * 0' do #At 7am on 1st day of every week
#   runner "MsrMailer.send_report('makerspace@uottawa.ca', 'hanis@uottawa.ca', ReportGenerator.new_user_report,
#   				ReportGenerator.lab_session_report,
#   				ReportGenerator.faculty_frequency_report, ReportGenerator.gender_frequency_report,
#           ReportGenerator.unique_visitors_report).deliver_now"
# end
#
# every '0 7 * * 0' do #At 7am of first day of every week
#   runner "MsrMailer.send_training_report('brunsfield@uottawa.ca', 'MTC@uottawa.ca', 'makerspace@uottawa.ca', 'hanis@uottawa.ca',
#                                         'ReportGenerator.training_report').deliver_now"
# end

# At 7am of First day of every month
# every '0 7 1 * *' do
every 1.month do
  runner "MsrMailer.send_monthly_report(hanis@uottawa.ca', 'bruno.mrlima@gmail.com', 'makerspace@uottawa.ca', ReportGenerator.new_user_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month),
          ReportGenerator.unique_visitors_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month),
          ReportGenerator.lab_session_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month),
          ReportGenerator.faculty_frequency_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month),
          ReportGenerator.gender_frequency_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month),
          ReportGenerator.makerspace_training_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month),
          ReportGenerator.mtc_training_report(1.month.ago.beginning_of_month, 1.month.ago.end_of_month)).deliver_now"

end

# At 7am of First day of every week
every :monday, :at => '7am' do
  runner "MsrMailer.send_weekly_report('hanis@uottawa.ca', 'bruno.mrlima@gmail.com', 'makerspace@uottawa.ca', ReportGenerator.new_user_report,
          ReportGenerator.unique_visitors_report,
          ReportGenerator.lab_session_report,
          ReportGenerator.faculty_frequency_report,
          ReportGenerator.gender_frequency_report,
          ReportGenerator.makerspace_training_report,
          ReportGenerator.mtc_training_report).deliver_now"
end


# At 7:30am of First day of every week
every :monday, :at => '7am' do
  runner "MsrMailer.send_training_report('hanis@uottawa.ca', 'bruno.mrlima@gmail.com','brunsfield@uottawa.ca', 'MTC@uottawa.ca', 'makerspace@uottawa.ca', ReportGenerator.makerspace_training_report, ReportGenerator.mtc_training_report).deliver_now"
end

every :monday, :at => '11:45am' do
  runner "MsrMailer.send_checklist_reminder('kpara084@uOttawa.ca').deliver_now"
end

every :monday, :at => '7:45pm' do
  runner "MsrMailer.send_checklist_reminder('ngnyr040@uOttawa.ca').deliver_now"
end

every :tuesday, :at => '11:45am' do
  runner "MsrMailer.send_checklist_reminder('mghod021@uOttawa.ca').deliver_now"
end

every :tuesday, :at => '7:45pm' do
  runner "MsrMailer.send_checklist_reminder('sbouc057@uOttawa.ca').deliver_now"
end

every :wednesday, :at => '11:45am' do
  runner "MsrMailer.send_checklist_reminder('bmont037@uOttawa.ca').deliver_now"
end

every :wednesday, :at => '7:45pm' do
  runner "MsrMailer.send_checklist_reminder('jpool092@uOttawa.ca').deliver_now"
end

every :thursday, :at => '11:45am' do
  runner "MsrMailer.send_checklist_reminder('mghod021@uOttawa.ca').deliver_now"
end

every :thursday, :at => '7:45pm' do
  runner "MsrMailer.send_checklist_reminder('inku036@uOttawa.ca').deliver_now"
end

every :friday, :at => '11:45am' do
  runner "MsrMailer.send_checklist_reminder('bsami021@uOttawa.ca').deliver_now"
end

every :friday, :at => '7:45pm' do
  runner "MsrMailer.send_checklist_reminder('inku036@uOttawa.ca').deliver_now"
end

every :sunday, :at => '10:45am' do
  runner "MsrMailer.send_checklist_reminder('jlian009@uOttawa.ca').deliver_now"
end

every :sunday, :at => '4:45pm' do
  runner "MsrMailer.send_checklist_reminder('slema053@uOttawa.ca').deliver_now"
end

every :tuesday, :at => '5:53pm' do
  runner "MsrMailer.send_checklist_reminder('bmont037@uottawa.ca').deliver_now"
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
