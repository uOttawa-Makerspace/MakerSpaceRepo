# frozen_string_literal: true

namespace :memberships do
  # Without an argument it only reads: it changes no row and calls no outside service. Of each member and tier pair
  # with more than one pending membership, the row checkout serves (the oldest) is kept and the others are listed to
  # close. With [apply] each extra row has its Shopify draft closed and is marked failed, with a recorded change
  # (Membership::DuplicateClosure); no row is deleted. Apply needs CONFIRM_MAX_DELETES of at least the number of
  # extra rows, and stops at the first draft that is paid. Safe to run again. See doc/maintenance.md.
  desc "List the member and tier pairs with more than one pending membership; with [apply] (and CONFIRM_MAX_DELETES) " \
       "close the extra rows: rake memberships:pending_duplicates[apply]"
  task :pending_duplicates, [:mode] => :environment do |_, args|
    abort 'usage: rake memberships:pending_duplicates[apply]  (no argument only lists)' unless [nil, '', 'apply'].include?(args[:mode])

    cap = ENV.fetch('CONFIRM_MAX_DELETES', '0')
    abort 'CONFIRM_MAX_DELETES must be a whole number' unless cap.match?(/\A\d+\z/)

    cleanup = Membership::DuplicateCleanup.new
    cleanup.list
    next unless args[:mode] == 'apply'

    begin
      outcomes = cleanup.apply!(max_closes: cap.to_i)
      abort 'some extra rows are still pending (see above); run again once Shopify answers' if outcomes.keys.any? { |o| o != :closed }
    rescue Membership::DuplicateCleanup::TooMany => e
      abort "#{e.message}: nothing was changed. Review the list, then run again with CONFIRM_MAX_DELETES=#{cleanup.extra_count}"
    rescue Membership::DuplicateCleanup::DraftPaid => e
      abort "#{e.message}. That membership is left pending for its order; settle it with the maintainers, then run again"
    end
  end

  # Puts back the rows memberships:pending_duplicates[apply] closed, from their membership_duplicate_closures records.
  # Without an argument it only lists what it would do. A row changed since its closure is refused, and so is one
  # whose member and tier already hold a pending row once the unique index exists, and one whose membership was deleted.
  # Apply needs CONFIRM_MAX_RESTORES of at least the number of rows listed. Restored rows are exactly as before,
  # updated_at included, so the stale checkout expiry treats them as it would have. Safe to run again.
  desc "List the closed duplicate memberships; with [apply] (and CONFIRM_MAX_RESTORES) put them back to pending " \
       "(their Shopify drafts stay deleted): rake memberships:restore_duplicate_closures[apply]"
  task :restore_duplicate_closures, [:mode] => :environment do |_, args|
    abort 'usage: rake memberships:restore_duplicate_closures[apply]  (no argument only lists)' unless [nil, '', 'apply'].include?(args[:mode])

    cap = ENV.fetch('CONFIRM_MAX_RESTORES', '0')
    abort 'CONFIRM_MAX_RESTORES must be a whole number' unless cap.match?(/\A\d+\z/)

    restore = Membership::DuplicateRestore.new
    next restore.list unless args[:mode] == 'apply'

    begin
      outcomes = restore.apply!(max_restores: cap.to_i)
      abort 'some rows were not restored (see above)' if outcomes.keys.any? { |o| o != :restored }
    rescue Membership::DuplicateRestore::TooMany => e
      abort "#{e.message}: nothing was changed. Review the list, then run again with CONFIRM_MAX_RESTORES=#{restore.count}"
    end
  end
end
