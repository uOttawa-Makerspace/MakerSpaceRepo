# frozen_string_literal: true

namespace :counters do
  desc "Compare the stored like and vote counters with their rows. Only lists the differences unless run as " \
       "rake counters:recount[apply], which first writes the old values to tmp/counter_recount_<time>.csv"
  task :recount, [:mode] => :environment do |_task, args|
    abort "usage: rake counters:recount[apply]  (no argument only lists)" unless [nil, "", "apply"].include?(args[:mode])

    recount = CounterRecount.new
    if args[:mode] == "apply"
      path = Rails.root.join("tmp", "counter_recount_#{Time.current.strftime('%Y%m%d%H%M%S')}.csv")
      found = recount.apply!(path)
      puts "old values written to #{path}"
    else
      found = recount.differences
    end
    found.each { |d| puts "#{d.kind} #{d.id}: stored #{d.stored}, counted #{d.counted}" }
    puts "#{found.size} counter(s) #{args[:mode] == 'apply' ? 'corrected' : 'differ (nothing changed)'}"
  end
end
