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

  it "keeps one membership of a training session both users attended, and moves the others" do
    shared = create(:training_session)
    only_duplicate = create(:training_session)
    shared.users << primary
    shared.users << duplicate
    only_duplicate.users << duplicate

    merge

    rows = ActiveRecord::Base.connection.select_rows(
      "SELECT training_session_id, user_id FROM training_sessions_users ORDER BY training_session_id"
    )
    expect(rows).to contain_exactly([shared.id, primary.id], [only_duplicate.id, primary.id])
  end

  it "merges tracks of a module both users started without losing a completion" do
    shared_module = create(:learning_module)
    only_duplicate_module = create(:learning_module)
    create(:learning_module_track, user: primary, learning_module: shared_module)
    create(:learning_module_track, :completed, user: duplicate, learning_module: shared_module)
    moved = create(:learning_module_track, user: duplicate, learning_module: only_duplicate_module)

    merge

    expect(primary.learning_module_tracks.where(learning_module: shared_module).pluck(:status)).to eq(["completed"])
    expect(moved.reload.user_id).to eq(primary.id)
    expect(LearningModuleTrack.where(user_id: duplicate.id)).to be_empty
  end

  it "does not drop a row the primary does not have" do
    session = create(:training_session)
    session.users << duplicate
    merge
    expect(ActiveRecord::Base.connection.select_rows("SELECT user_id FROM training_sessions_users")).to eq([[primary.id]])
  end

  it "leaves other users' references alone" do
    other = create(:user)
    key = create(:key, supervisor: other, space: create(:space))
    merge
    expect(key.reload.supervisor_id).to eq(other.id)
  end
end
