# frozen_string_literal: true

namespace :counters do
  desc "Compare the stored like and vote counters with their rows. Only lists the differences unless run as " \
       "rake counters:recount[apply], which records the old and new value of every corrected row in the " \
       "counter_recount_corrections table (and in tmp/counter_recount_<time>_<random>.csv)"
  task :recount, [:mode] => :environment do |_task, args|
    unless [nil, "", "apply"].include?(args[:mode])
      abort "usage: rake counters:recount[apply]  (no argument only lists)"
    end

    recount = CounterRecount.new
    if args[:mode] == "apply"
      stamp = Time.current.strftime("%Y%m%d%H%M%S")
      path = Rails.root.join("tmp", "counter_recount_#{stamp}_#{SecureRandom.hex(3)}.csv")
      found = recount.apply!(path)
      puts "changes also written to #{path}"
    else
      found = recount.differences
    end
    found.each { |d| puts "#{d.kind} #{d.id}: stored #{d.stored}, counted #{d.counted}" }
    puts "#{found.size} counter(s) #{args[:mode] == 'apply' ? 'corrected' : 'differ (nothing changed)'}"
  end
end
