# frozen_string_literal: true

require "rails_helper"
require "rake"

# users:merge_duplicates moves everything of a duplicate user to the user it keeps and
# then deletes the duplicate. With foreign keys on the columns that have no User
# association (supervisor_id, admin_id), those must move too or the delete is refused.
RSpec.describe "users:merge_duplicates" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("users:merge_duplicates")
  end

  let(:primary) { create(:user) }
  let(:duplicate) { create(:user) }

  def merge
    send(:merge_record, primary, duplicate)
  end

  around do |example|
    original_stdout = $stdout
    $stdout = StringIO.new
    example.run
  ensure
    $stdout = original_stdout
  end

  it "moves keys, key requests and proposals that name the duplicate only as supervisor or admin" do
    key = create(:key, supervisor: duplicate, space: create(:space))
    proposal = create(:project_proposal, admin: duplicate)

    merge

    expect(User.unscoped.exists?(duplicate.id)).to be(false)
    expect(key.reload.supervisor_id).to eq(primary.id)
    expect(proposal.reload.admin_id).to eq(primary.id)
  end

  it "moves what the user associations cover as before" do
    task = create(:volunteer_task, user: duplicate)
    merge
    expect(task.reload.user_id).to eq(primary.id)
    expect(User.unscoped.exists?(duplicate.id)).to be(false)
  end

  it "leaves other users' references alone" do
    other = create(:user)
    key = create(:key, supervisor: other, space: create(:space))
    merge
    expect(key.reload.supervisor_id).to eq(other.id)
  end
end
