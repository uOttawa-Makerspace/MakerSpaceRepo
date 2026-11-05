# frozen_string_literal: true

require "rails_helper"

# Chunk 16: the MsrMailer messages sent by the repository / project flows,
# pinned by delivered outcome (recipient, subject, body). The controller specs
# pin when each one is (not) sent.
RSpec.describe MsrMailer, type: :mailer do
  let(:user) { create(:user, :regular_user, name: "Mailee Person") }
  let(:skill) { create(:skill, name: "Technical") }
  let(:project) { create(:proficient_project, title: "Mail project", training: create(:training, skill: skill)) }

  def deliver(message)
    ActionMailer::Base.deliveries.clear
    message.deliver_now
    ActionMailer::Base.deliveries.last
  end

  it "send_kit_email greets the user and names the project looked up by id" do
    mail = deliver(MsrMailer.send_kit_email(user, project.id))
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to eq("Your proficient project kit order")
    expect(mail.body.encoded).to include("Mailee Person").and include("Mail project".capitalize)
  end

  it "send_kit_email raises for an unknown project id when rendered" do
    expect { MsrMailer.send_kit_email(user, 0).deliver_now }.to raise_error(ActionView::Template::Error, /Couldn.t find ProficientProject/)
  end

  describe "send_results_pp" do
    let(:oi) { create(:order_item, order: create(:order, :completed, user_id: user.id), proficient_project: project, admin_comments: "Well <b>done</b><script>x()</script>") }

    it "says passed, links to the progress page and sanitizes admin comments" do
      mail = deliver(MsrMailer.send_results_pp(oi, user, "Passed"))
      expect(mail.to).to eq([user.email])
      expect(mail.subject).to eq("Your Proficient Project Results")
      body = mail.body.encoded
      expect(body).to include("passed").and include("/development_programs/skills")
      expect(body).to include("Well <b>done</b>")
      expect(body).not_to include("<script>")
    end

    it "says failed for 'Failed'" do
      mail = deliver(MsrMailer.send_results_pp(oi, user, "Failed"))
      expect(mail.body.encoded).to include("failed")
    end

    it "shows 'None' when the admin comment is the empty string" do
      oi.update_columns(admin_comments: "")
      expect(deliver(MsrMailer.send_results_pp(oi, user, "Passed")).body.encoded).to include("None")
    end
  end

  describe "proficient project evaluation" do
    it "routes the admin notice by skill: technical -> makerspace@, otherwise mtc@" do
      expect(deliver(MsrMailer.send_admin_pp_evaluation(project)).to).to eq(["makerspace@uottawa.ca"])
      skill.update!(name: "Professional")
      expect(deliver(MsrMailer.send_admin_pp_evaluation(project.reload)).to).to eq(["mtc@uottawa.ca"])
    end

    it "emails the submitter a receipt" do
      mail = deliver(MsrMailer.send_user_pp_evaluation(project, user))
      expect(mail.to).to eq([user.email])
      expect(mail.subject).to eq("Your Proficient Project Request")
    end
  end

  it "send_new_project_proposals goes to makerlab@uottawa.ca" do
    mail = deliver(MsrMailer.send_new_project_proposals)
    expect(mail.to).to eq(["makerlab@uottawa.ca"])
    expect(mail.subject).to eq("New Project Proposal")
  end

  it "repo_report is sent FROM the reporter's address to the MakerRepo inbox" do
    repo = create(:repository, owner: user, title: "Reported Repo")
    mail = deliver(MsrMailer.repo_report(repo, user))
    expect(mail.from).to eq([user.email])
    expect(mail.to).to eq(["uottawa.makerepo@gmail.com"])
    expect(mail.subject).to eq("Repository Reported Repo reported")
  end
end
