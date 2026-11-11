# frozen_string_literal: true

namespace :memberships do
  desc "List the member and tier pairs with more than one pending membership (read only): rake memberships:pending_duplicates"
  task pending_duplicates: :environment do
    pairs = Membership.pending_duplicates
    puts "no member and tier pair has more than one pending membership" if pairs.empty?
    pairs.each do |user_id, tier_id, ids|
      puts "user #{user_id}, tier #{tier_id}: #{ids.size} pending (ids #{ids.join(', ')})"
    end
    puts "#{pairs.size} pairs, #{pairs.sum { |_, _, ids| ids.size }} pending memberships" if pairs.any?
  end
end
