# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe CounterRecount do
  include ActiveSupport::Testing::TimeHelpers

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

  describe "#apply!" do
    let(:path) { Rails.root.join("tmp/counter_recount_spec_#{SecureRandom.hex(4)}.csv") }

    after { FileUtils.rm_f(path) }

    before do
      repo.update_column(:like, 7)
      comment.update_column(:upvote, -4)
    end

    it "records the old and the written value of each corrected row" do
      travel_to(Time.zone.local(2027, 1, 5, 12)) do
        described_class.new.apply!(path)

        rows = CounterRecountCorrection.order(:table_name).map do |c|
          [c.table_name, c.row_id, c.column_name, c.old_value, c.new_value, c.run_at]
        end
        expect(rows)
          .to eq([["comments", comment.id, "upvote", -4, 1, Time.current],
                  ["repositories", repo.id, "like", 7, 3, Time.current]])
      end
    end

    it "records and writes the value counted when the row is locked, not the one in the earlier list" do
      recount = described_class.new
      stale = [described_class::Difference.new("like", repo.id, 9, 99)]
      allow(recount).to receive(:differences).and_return(stale)

      applied = recount.apply!(path)

      expect(repo.reload.like).to eq(3)
      expect(applied.map(&:to_a)).to eq([["like", repo.id, 7, 3]])
      expect(CounterRecountCorrection.sole.attributes.values_at("old_value", "new_value")).to eq([7, 3])
    end

    it "records nothing for a counter that was corrected since the list was made" do
      recount = described_class.new
      stale = [described_class::Difference.new("like", repo.id, 7, 3)]
      repo.update_column(:like, 3)
      allow(recount).to receive(:differences).and_return(stale)

      expect(recount.apply!(path)).to be_empty
      expect(CounterRecountCorrection.count).to eq(0)
    end

    it "records a counter that was NULL as no old value" do
      repo.update_column(:like, nil)

      described_class.new.apply!(path)

      expect(CounterRecountCorrection.find_by(table_name: "repositories").old_value).to be_nil
    end

    it "keeps every record when the file cannot be written, and refuses to overwrite a file" do
      File.write(path, "keep")

      expect { described_class.new.apply!(path) }.to raise_error(Errno::EEXIST)
      expect(File.read(path)).to eq("keep")
      expect(repo.reload.like).to eq(7)
      expect(CounterRecountCorrection.count).to eq(0)
    end

    it "refuses a table other than repositories and comments in the archive" do
      expect do
        CounterRecountCorrection.create!(table_name: "users", row_id: 1, column_name: "like", new_value: 1,
                                         run_at: Time.current)
      end.to raise_error(ActiveRecord::StatementInvalid, /check/i)
    end

    it "never changes a stored record" do
      described_class.new.apply!(path)

      expect { CounterRecountCorrection.first.update!(new_value: 0) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
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

    it "also keeps the old values in the archive table" do
      run_task("apply")

      expect(CounterRecountCorrection.sole.attributes.values_at("table_name", "row_id", "old_value", "new_value"))
        .to eq(["repositories", repo.id, 7, 3])
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
