# frozen_string_literal: true

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

set :whenever_identifier, -> { "#{fetch(:application)}_#{fetch(:stage)}" }
set :output, 'log/cron_log.log'
env :PATH, ENV['PATH']

every 1.month do
  runner "MsrMailer.send_monthly_report(['hanis@uottawa.ca', 'bruno.mrlima@gmail.com']).deliver_now"
end

every :hour do
  rake 'popular_hours:populate'
end

every 1.month do
  rake 'confirmed_users:remind'
end

# At 7am of First day of every week
every :monday, at: '7am' do
  runner "MsrMailer.send_weekly_report(['hanis@uottawa.ca', 'bruno.mrlima@gmail.com']).deliver_now"
end

# At 7:30am of First day of every week
every :monday, at: '7am' do
  runner "MsrMailer.send_training_report(['hanis@uottawa.ca', 'bruno.mrlima@gmail.com','brunsfield@uottawa.ca', 'MTC@uottawa.ca]).deliver_now"
end

every :sunday, at: '1am' do
  rake 'active_volunteers:check_volunteers_status'
end

every :day, at: '2am' do
  rake 'active_volunteers:check_volunteers_status'
end

every :day, at: '11:59pm' do
  rake 'exams:check_expired_exams'
end

every :day, at: '3am' do
  rake 'badge:get_data'
  rake 'badge:get_and_update_badge_templates'
end

every :day, at: '9am' do
  rake 'print_order_notifications:two_weeks_reminder'
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
