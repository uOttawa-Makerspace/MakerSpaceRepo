# frozen_string_literal: true

namespace :volunteer_awards do
  # Lists task awards (CC money rows) that a user holds more than once for the same task. It only reads: it
  # changes and removes nothing. The listing shows ids so the maintainers can decide, row by row, what to do.
  desc "List duplicate volunteer task awards (read only)"
  task duplicates: :environment do
    groups = CcMoney.duplicate_task_awards
    if groups.empty?
      puts "No user holds a task award more than once."
    else
      puts "#{groups.size} user and task pair(s) hold more than one award:"
      groups.each do |user_id, task_id, ids|
        puts "  user_id=#{user_id} volunteer_task_id=#{task_id} cc_money ids=#{ids.join(',')}"
      end
    end
  end
end
