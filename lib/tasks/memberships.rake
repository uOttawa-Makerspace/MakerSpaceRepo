# frozen_string_literal: true

namespace :memberships do
  # Reads only: changes no row and calls no outside service. The row marked "keep" is the one claim_pending serves
  # (the lowest id); the others are the ones a later, approved step would close.
  desc "List the member and tier pairs with more than one pending membership (read only): rake memberships:pending_duplicates"
  task pending_duplicates: :environment do
    helpers = ActionController::Base.helpers
    pairs = Membership.pending_duplicates
    puts "no member and tier pair has more than one pending membership" if pairs.empty?
    pairs.each do |user_id, tier_id, ids|
      puts "user #{user_id}, tier #{tier_id}: #{ids.size} pending (ids #{ids.join(', ')})"
      Membership.where(id: ids).order(:id).each_with_index do |membership, index|
        puts "  membership #{membership.id} #{index.zero? ? 'keep' : 'extra'} " \
             "created #{membership.created_at.utc.iso8601} draft #{membership.shopify_draft_order_id || 'none'}"
      end
    end
    next if pairs.empty?

    puts "#{helpers.pluralize(pairs.size, 'pair')}, " \
         "#{helpers.pluralize(pairs.sum { |_, _, ids| ids.size }, 'pending membership')}"
  end
end
