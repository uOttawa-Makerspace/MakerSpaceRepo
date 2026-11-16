# frozen_string_literal: true

class Membership
  # What `rake memberships:pending_duplicates` lists and, with [apply], closes (the rule is in
  # Membership::Deduplication). The listing names rows by id and Shopify draft id only.
  #
  #   cleanup = Membership::DuplicateCleanup.new(out: $stdout)
  #   cleanup.list                      prints every pair, the row kept and the extra rows to close; changes nothing
  #   cleanup.apply!(max_closes: n)     closes the extra rows, one at a time, and returns the outcomes counted
  #
  # apply! raises TooMany, changing nothing, when more than `max_closes` rows would be closed, and stops with
  # DraftPaid at the first extra row whose draft is paid (that row is left pending; the rows before it stay closed).
  # A listed row that no longer exists is reported and skipped.
  class DuplicateCleanup
    class TooMany < StandardError; end
    class DraftPaid < StandardError; end

    # `kept`: the row checkout serves (nil if none is pending any more); `extras`: the other listed rows, by id;
    # `missing`: listed ids with no row any more.
    Pair = Data.define(:user_id, :tier_id, :ids, :kept, :extras, :missing)

    def initialize(out: $stdout)
      @out = out
    end

    def pairs
      @pairs ||= Membership.pending_duplicates.map { |user_id, tier_id, ids| build_pair(user_id, tier_id, ids) }
    end

    def extra_count = pairs.sum { |pair| pair.extras.size }

    def list
      return @out.puts('no member and tier pair has more than one pending membership') if pairs.empty?

      pairs.each { |pair| list_pair(pair) }
      @out.puts "#{pluralize(pairs.size, 'pair')}, #{pluralize(pairs.sum { |pair| pair.ids.size }, 'pending membership')}, " \
                "#{pluralize(extra_count, 'extra row')} to close"
    end

    def apply!(max_closes:)
      raise TooMany, "#{pluralize(extra_count, 'extra row')} would be closed, more than #{max_closes}" if extra_count > max_closes

      outcomes = pairs.flat_map { |pair| close_extras(pair) }.tally
      @out.puts "outcomes: #{outcomes.map { |outcome, count| "#{outcome} #{count}" }.join(', ').presence || 'none'}"
      outcomes
    end

    private

    def build_pair(user_id, tier_id, ids)
      rows = Membership.where(id: ids).order(:id).to_a
      kept = Membership.served_pending(user_id, tier_id)
      Pair.new(user_id: user_id, tier_id: tier_id, ids: ids, kept: kept,
               extras: kept ? rows.reject { |row| row.id == kept.id } : [], missing: ids - rows.map(&:id))
    end

    def list_pair(pair)
      @out.puts "user #{pair.user_id}, tier #{pair.tier_id}: #{pair.ids.size} pending (ids #{pair.ids.join(', ')})"
      list_row(pair.kept, 'keep (the row checkout serves: oldest pending)') if pair.kept
      pair.extras.each { |membership| list_row(membership, 'close') }
      pair.missing.each { |id| @out.puts "  membership #{id} no longer exists: skipped" }
    end

    def list_row(membership, role)
      @out.puts "  membership #{membership.id} #{role} created #{membership.created_at.utc.iso8601} " \
                "updated #{membership.updated_at.utc.iso8601} draft #{membership.shopify_draft_order_id || 'none'}"
    end

    def close_extras(pair)
      pair.extras.map do |membership|
        outcome = membership.close_as_duplicate_of(pair.kept)
        @out.puts "  membership #{membership.id} #{outcome} draft #{membership.shopify_draft_order_id || 'none'}"
        raise DraftPaid, "membership #{membership.id}: draft #{membership.shopify_draft_order_id} is paid; stopped" if outcome == :paid

        outcome
      end
    end

    def pluralize(count, word) = ActionController::Base.helpers.pluralize(count, word)
  end
end
