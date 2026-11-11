# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe CounterRecount do
  let(:repo) { create(:repository) }
  let(:comment) { create(:comment, repository: repo) }
  let(:fans) { create_list(:user, 3, :regular_user) }

  before do
    fans.each { |fan| Like.give(repo, fan) }
    Upvote.cast(fans[0], comment, false)
    Upvote.cast(fans[1], comment, false)
    Upvote.cast(fans[2], comment, true)
    create(:comment, repository: repo)
  end

  it "lists nothing when the counters match their rows" do
    expect(described_class.new.differences).to be_empty
  end

  it "lists each counter that differs, with the stored and the counted value" do
    repo.update_column(:like, 7)
    comment.update_column(:upvote, -4)

    expect(described_class.new.differences.map(&:to_a))
      .to eq([["like", repo.id, 7, 3], ["upvote", comment.id, -4, 1]])
  end

  it "counts a hidden repository and a repository nobody liked" do
    unliked = create(:repository)
    unliked.update_column(:like, 2)
    repo.hide!(by: fans.first)
    repo.update_column(:like, 0)

    expect(described_class.new.differences.map(&:to_a))
      .to contain_exactly(["like", repo.id, 0, 3], ["like", unliked.id, 2, 0])
  end

  describe "the rake task" do
    let(:task) { Rake::Task["counters:recount"] }

    before do
      Rails.application.load_tasks unless Rake::Task.task_defined?("counters:recount")
      task.reenable
      repo.update_column(:like, 7)
    end

    after { Dir[Rails.root.join("tmp/counter_recount_*.csv")].each { |f| File.delete(f) } }

    def run_task(*args)
      out = StringIO.new
      original = $stdout
      $stdout = out
      task.invoke(*args)
      out.string
    ensure
      $stdout = original
    end

    it "only lists the differences by default and changes nothing" do
      output = run_task

      expect(output).to include("like #{repo.id}: stored 7, counted 3").and include("1 counter(s) differ")
      expect(repo.reload.like).to eq(7)
      expect(Dir[Rails.root.join("tmp/counter_recount_*.csv")]).to be_empty
    end

    it "writes the old values to a file and then the counted values when told to apply" do
      output = run_task("apply")

      expect(repo.reload.like).to eq(3)
      file = Dir[Rails.root.join("tmp/counter_recount_*.csv")].sole
      expect(output).to include(file).and include("1 counter(s) corrected")
      expect(File.read(file)).to eq("kind,id,stored,counted\nlike,#{repo.id},7,3\n")
      expect(described_class.new.differences).to be_empty
    end

    it "can be run again after applying and changes nothing more" do
      run_task("apply")
      task.reenable

      expect(run_task("apply")).to include("0 counter(s) corrected")
    end

    it "refuses an unknown argument" do
      expect { run_task("now") }.to raise_error(SystemExit)
      expect(repo.reload.like).to eq(7)
    end
  end
end
