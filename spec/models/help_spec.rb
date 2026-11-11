require "rails_helper"

RSpec.describe Help, type: :model do
  def valid_attrs(**over)
    { name: "Pat", email: "pat@example.test", subject: "A long enough subject", comments: "Something broke" }.merge(over)
  end

  it "is valid with name, email, subject (10+ chars) and comments" do
    expect(Help.new(valid_attrs)).to be_valid
  end

  it "validates name length, email format, subject length and comments presence" do
    expect(Help.new(valid_attrs(name: "P"))).not_to be_valid
    expect(Help.new(valid_attrs(email: "nope"))).not_to be_valid
    expect(Help.new(valid_attrs(subject: "short"))).not_to be_valid
    expect(Help.new(valid_attrs(comments: ""))).not_to be_valid
  end

  it "saves without calling GitHub" do
    expect_any_instance_of(GithubIssuesService).not_to receive(:create_issue)
    help = Help.create!(valid_attrs)
    expect(help.gh_issue_number).to be_nil
  end

  it "opens a GitHub issue on file_issue and stores the issue number (stubbed in test)" do
    help = Help.create!(valid_attrs)
    expect(help.file_issue).to be(true)
    expect(help.reload.gh_issue_number.to_s).to eq("111")
  end

  it "keeps the saved report and adds an error when no issue number comes back" do
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return({ number: nil })
    help = Help.create!(valid_attrs)
    expect(help.file_issue).to be(false)
    expect(help.errors[:base]).to include("Internal error while submitting issue.")
    expect(help.reload.gh_issue_number).to be_nil
  end

  it "treats a failed GitHub call (false) as no issue" do
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue).and_return(false)
    expect(Help.create!(valid_attrs).file_issue).to be(false)
  end

  describe ".defang" do
    it "leaves plain text unchanged" do
      expect(Help.defang("Printer 3 won't start, 50% done")).to eq("Printer 3 won't start, 50% done")
    end

    it "breaks mentions and cross-references and escapes HTML" do
      expect(Help.defang("@a @b/c #1 <b>")).to eq("@\u200Da @\u200Db/c #\u200D1 &lt;b&gt;")
    end
  end

  it "passes the legacy text through untouched when defang_github_text is not set" do
    seen = nil
    allow_any_instance_of(GithubIssuesService).to receive(:create_issue) { |_s, **kw| seen = kw; { number: 1 } }
    help = Help.new(valid_attrs(comments: "hi @someone #1"))
    help.save!
    help.file_issue
    expect(seen[:reporter]).to eq(help.name)
    expect(seen[:title]).to eq(help.subject)
    expect(seen[:body]).to eq(help.comments)
    expect(seen[:body].to_plain_text).to include("@someone #1")
  end
end
