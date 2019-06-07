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

# every :thursday, :at => '1:12 pm' do
#   runner "MsrMailer.send_ommic.deliver_now"
# end
#

set :whenever_identifier, ->{ "#{fetch(:application)}_#{fetch(:stage)}" }
set :output, "log/cron_log.log"
env :PATH, ENV['PATH']

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

every :sunday, :at => '1am' do
  rake "active_volunteers:check_volunteers_status"
end

# Checklist Reminder

# emails list:
# Jared Poole: jaredpoole123@gmail.com
# Bruno Monteiro bmont037@uottawa.ca
# Kim	kpara084@uOttawa.ca	Monday	11:45
# Nic	ngnyr040@uOttawa.ca	Monday	7:45
# MG	mghod021@uOttawa.ca	Tuesday	11:45
# Sam	sbouc057@uOttawa.ca	Tuesday	7:45
# Bruno	bmont037@uOttawa.ca	Wednesday	11:45
# Jared	jaredpoole123@gmail.com or jpool092@uOttawa.ca	Wednesday	7:45
# MG	mghod021@uOttawa.ca	Thursday	11:45
# David 	inku036@uOttawa.ca	Thursday	7:45
# Bijan	bsami021@uOttawa.ca	Friday	11:45
# David 	inku036@uOttawa.ca	Friday	7:45
# Jenny	jlian009@uOttawa.ca	Sunday	10:45
# Simon	slema053@uOttawa.ca
# Niko nikoleeyow@Gmail.com
# Arthur art.fetiveau@gmail.com
# Sarah shodg076@uottawa.ca
#
# #########
# every :monday, :at => '9:45 am' do
#   runner "MsrMailer.send_checklist_reminder('jaredpoole123@gmail.com', 'bmont037@uottawa.ca').deliver_now"
# end
#
# every :monday, :at => '5:45 pm' do
#   runner "MsrMailer.send_checklist_reminder('nikoleeyow@gmail.com', 'bmont037@uottawa.ca').deliver_now"
# end
#
# every :tuesday, :at => '9:45 am' do
#   runner "MsrMailer.send_checklist_reminder('bmont037@uottawa.ca', 'bruno.mrlima@gmail.com').deliver_now"
# end
#
# every :tuesday, :at => '5:45 pm' do
#   runner "MsrMailer.send_checklist_reminder('mghod021@uottawa.ca', 'bmont037@uottawa.ca').deliver_now"
# end
#
# every :wednesday, :at => '9:45 am' do
#   runner "MsrMailer.send_checklist_reminder('bsami021@uottawa.ca', 'bmont037@uottawa.ca').deliver_now"
# end
#
# every :wednesday, :at => '5:45 pm' do
#   runner "MsrMailer.send_checklist_reminder('shodg076@uottawa.ca', 'bmont037@uottawa.ca').deliver_now"
# end
#
# every :thursday, :at => '9:45 am' do
#   runner "MsrMailer.send_checklist_reminder('bmont037@uottawa.ca', 'bruno.mrlima@gmail.com').deliver_now"
# end
#
# every :thursday, :at => '5:45 pm' do
#   runner "MsrMailer.send_checklist_reminder('sbouc057@uottawa.ca', 'bmont037@uottawa.ca').deliver_now"
# end
#
# every :friday, :at => '9:45 am' do
#   runner "MsrMailer.send_checklist_reminder('shodg076@uottawa.ca', 'bmont037@uottawa.ca').deliver_now"
# end
#
# every :friday, :at => '5:45 pm' do
#   runner "MsrMailer.send_checklist_reminder('nikoleeyow@gmail.com', 'bmont037@uottawa.ca').deliver_now"
# end
#
# every :sunday, :at => '10:15 am' do
#   runner "MsrMailer.send_checklist_reminder('jlian009@uottawa.ca', 'bmont037@uottawa.ca').deliver_now"
# end
#
# every :sunday, :at => '10:15 am' do
#   runner "MsrMailer.send_checklist_reminder('art.fetiveau@gmail.com', 'bmont037@uottawa.ca').deliver_now"
# end
#
# every :sunday, :at => '4:45 pm' do
#   runner "MsrMailer.send_checklist_reminder('jlian009@uottawa.ca', 'bmont037@uottawa.ca').deliver_now"
# end
#
# every :sunday, :at => '4:45 pm' do
#   runner "MsrMailer.send_checklist_reminder('art.fetiveau@gmail.com', 'bmont037@uottawa.ca').deliver_now"
# end
#
# ########

# every 10.minutes do
#   runner "MsrMailer.send_checklist_reminder('bmont037@uottawa.ca', 'bruno.mrlima@gmail.com').deliver_now"
# end

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
