# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "users:internal_without_proof" do
  before { Rails.application.load_tasks unless Rake::Task.task_defined?("users:internal_without_proof") }

  it "prints the ids of internal accounts without proof and a count, and changes nothing" do
    no_proof = create(:user, identity: "community_member", email: "x@example.com")
    no_proof.update_columns(identity: "staff_member")
    create(:user, identity: "faculty_member", email: "y@uottawa.ca")

    before = User.order(:id).pluck(:id, :identity, :email, :updated_at)
    output = capture_stdout_of_task

    expect(output.lines.map(&:chomp)).to eq([no_proof.id.to_s, "1 accounts with an internal identity and no proof"])
    expect(User.order(:id).pluck(:id, :identity, :email, :updated_at)).to eq(before)
  end

  def capture_stdout_of_task
    Rake::Task["users:internal_without_proof"].reenable
    original = $stdout
    $stdout = StringIO.new
    Rake::Task["users:internal_without_proof"].invoke
    $stdout.string
  ensure
    $stdout = original
  end
end
