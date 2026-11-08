# frozen_string_literal: true

require "rails_helper"

# A broad rescue (StandardError, Exception or a bare `rescue => e`) must not swallow
# the error: its body has to re-raise, or log or report it (report_unexpected,
# Rails.error, Rails.logger). This scans app/ and lib/ and fails on a new offender.
#
# SILENT_RESCUES lists the offenders that exist today, as file => count, each with the
# slice that removes it. The list only shrinks: a file that gains a silent rescue fails,
# and a file that no longer has one must be taken off the list.
module RescueGuard
  BROAD_RESCUE = /\A(\s*)rescue\b(?:\s*=>\s*\w+|\s+(?:StandardError|Exception)\b.*)?\s*(?:#.*)?\z/
  HANDLES_THE_ERROR = /\braise\b|report_unexpected|Rails\.error|Rails\.logger|\blogger\.|\.report\(|Airbrake/

  SILENT_RESCUES = {
    "app/controllers/admin/events_controller.rb" => 1, # err-b4
    "app/controllers/admin/uni_programs_controller.rb" => 1, # err-b4
    "app/controllers/repositories_controller.rb" => 2, # err-b5
    "app/controllers/staff_dashboard_controller.rb" => 1, # err-b3
    "app/helpers/calendar_helper.rb" => 2, # err-d
    "app/jobs/apply_processed_order_job.rb" => 1, # err-d
    "app/models/job_order/draft_sweep.rb" => 4, # err-d (one re-raises after the block, check)
    "app/models/locker_rental.rb" => 3, # err-d
    "app/models/processed_order.rb" => 1, # err-d
    "app/models/space.rb" => 2, # err-d
    "app/services/shop_order_applier.rb" => 1, # err-d
    "app/validators/recurrence_rule_validator.rb" => 1 # err-d
  }.freeze
end

RSpec.describe "Broad rescues" do
  # The number of broad rescue clauses in the file whose body neither re-raises nor logs.
  def silent_rescue_count(path)
    lines = File.readlines(path)
    lines.each_index.count do |i|
      match = RescueGuard::BROAD_RESCUE.match(lines[i])
      match && !RescueGuard::HANDLES_THE_ERROR.match?(rescue_body(lines, i, match[1].size))
    end
  end

  def rescue_body(lines, index, indent)
    body = lines.drop(index + 1).take_while { |l| l.strip.empty? || l[/\A\s*/].size > indent }
    body.join
  end

  def counts
    Dir[Rails.root.join("{app,lib}/**/*.rb")].to_h do |path|
      [Pathname(path).relative_path_from(Rails.root).to_s, silent_rescue_count(path)]
    end.reject { |_, count| count.zero? }
  end

  it "has no silent broad rescue beyond the allowlist, and the allowlist has no stale entry" do
    expect(counts).to eq(RescueGuard::SILENT_RESCUES)
  end

  it "recognises a silent rescue and a handled one" do
    silent = ["  rescue StandardError => e\n", "    nil\n", "  end\n"]
    handled = ["  rescue => e\n", "    report_unexpected(e)\n", "  end\n"]
    expect(RescueGuard::BROAD_RESCUE).to match(silent.first)
    expect(RescueGuard::HANDLES_THE_ERROR).not_to match(rescue_body(silent, 0, 2))
    expect(RescueGuard::HANDLES_THE_ERROR).to match(rescue_body(handled, 0, 2))
  end
end
