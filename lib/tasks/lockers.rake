# frozen_string_literal: true

namespace :lockers do
  desc 'Mail the renters of rentals that expired in the last LockerRental::EXPIRY_NOTICE_WINDOW and mark them notified'
  task notify_expired_rentals: :environment do
    puts 'Checking for expired locker rentals...'
    count = LockerRental.notify_expired_rentals!(log: method(:puts))
    puts "Done! Notified #{count} expired rental(s)."
  end

  desc 'List the open locker drafts made before drafts carried a rental marker that no rental stores (changes nothing); ' \
       'rake lockers:untagged_drafts[apply] closes them after the list is approved. Exit 1 while any is unresolved, 2 skipped'
  task :untagged_drafts, [:mode] => :environment do |_task, args|
    abort 'usage: rake lockers:untagged_drafts[apply]  (no argument only lists)' unless [nil, '', 'apply'].include?(args[:mode])

    apply = args[:mode] == 'apply'
    cap = ENV['CONFIRM_MAX_DELETES']
    abort 'CONFIRM_MAX_DELETES must be a whole number' if cap && !cap.match?(/\A\d+\z/)

    report, sweep = LockerRental::UntaggedDraftSweep.run(apply: apply, **(cap ? { max_deletes: cap.to_i } : {}))
    if report.skipped
      puts 'skipped: another sweep is running'
      exit(2)
    end
    sweep.listed.each { |gid| puts "would close: #{gid}" }
    sweep.closed.each { |gid| puts "closed: #{gid}" }
    report.counts.each { |outcome, n| puts "#{outcome}: #{n}" }
    report.unresolved.each { |line| warn "not resolved: #{line}" }
    puts apply ? 'applied: listed drafts were closed' : 'nothing changed (add [apply] to close the listed drafts)'
    exit(1) unless report.ok?
  end
end
