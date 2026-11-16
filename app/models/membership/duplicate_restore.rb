# frozen_string_literal: true

class Membership
  # What `rake memberships:restore_duplicate_closures` lists and, with [apply], puts back: every closure of a duplicate
  # pending membership not restored yet (Membership::DuplicateClosure#restore). The Shopify draft of a restored row
  # stays deleted; the next checkout for that row makes a new one. The listing names rows by id and draft id only.
  #
  #   restore = Membership::DuplicateRestore.new(out: $stdout)
  #   restore.list      prints each closure and what a restore would do; changes nothing
  #   restore.apply!(max_restores: n)   restores each closure in turn and returns the outcomes counted; raises
  #                                     TooMany, changing nothing, when more than n closures are listed
  class DuplicateRestore
    class TooMany < StandardError; end

    DRAFT_NOTE = 'restored rows are exactly as before, including for the stale checkout expiry; ' \
                 'the Shopify draft stays deleted and the next checkout for the row makes a new one'

    def initialize(out: $stdout)
      @out = out
    end

    def closures
      @closures ||= Membership::DuplicateClosure.unrestored.includes(:membership).order(:id).to_a
    end

    # How many closures are not restored yet (counted without loading them).
    def count = Membership::DuplicateClosure.unrestored.count

    def list
      return @out.puts('no closed duplicate membership to restore') if closures.empty?

      closures.each { |closure| @out.puts "#{describe(closure)}: #{closure.restorable_state}" }
      @out.puts "#{closures.size} to look at; #{DRAFT_NOTE}"
    end

    def apply!(max_restores:)
      raise TooMany, "#{count} closures would be restored, more than #{max_restores}" if count > max_restores

      outcomes = closures.map do |closure|
        outcome = closure.restore
        @out.puts "#{describe(closure)}: #{outcome}"
        outcome
      end.tally
      @out.puts "outcomes: #{outcomes.map { |outcome, count| "#{outcome} #{count}" }.join(', ').presence || 'none'}; #{DRAFT_NOTE}"
      outcomes
    end

    private

    def describe(closure)
      "membership #{closure.membership_id} (closed #{closure.closed_at.utc.iso8601}, kept #{closure.kept_membership_id}, " \
        "draft #{closure.shopify_draft_order_id || 'none'}) back to #{closure.previous_status}"
    end
  end
end
