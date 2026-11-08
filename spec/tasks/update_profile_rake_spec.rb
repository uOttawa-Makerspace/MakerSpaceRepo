# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "update_profile:send_emails" do
  include ActiveSupport::Testing::TimeHelpers

  let!(:regular) { create(:user, :regular_user) }
  let!(:other) { create(:user, :regular_user) }
  let!(:dormant) { create(:user, :regular_user).tap { |u| User.where(id: u.id).update_all(active: false) } }
  let!(:deactivated) { create(:user, :regular_user).tap(&:deactivate!) }

  before { Rails.application.load_tasks unless Rake::Task.task_defined?("update_profile:send_emails") }

  def send_emails(*args, force: false)
    Rake::Task["update_profile:send_emails"].reenable
    ENV["FORCE"] = "1" if force
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { Rake::Task["update_profile:send_emails"].invoke(*args) }
    ActionMailer::Base.deliveries.flat_map(&:bcc)
  ensure
    ENV.delete("FORCE")
  end

  it "works with no argument and BCCs active users who are not deactivated" do
    sent = send_emails

    expect(sent).to include(regular.email, other.email)
    expect(sent).not_to include(deactivated.email, dormant.email)
  end

  it "leaves out the addresses given as the argument" do
    expect(send_emails("#{other.email} nobody@example.test")).not_to include(other.email)
  end

  it "mails nobody on a second run the same year" do
    send_emails
    expect(send_emails).to be_empty
  end

  it "mails everyone again when forced" do
    send_emails
    expect(send_emails(force: true)).to include(regular.email)
  end

  it "mails again the next year" do
    send_emails
    travel_to(1.year.from_now) { expect(send_emails).to include(regular.email) }
  end

  it "skips users already handled when a run was interrupted" do
    Setting.set("bulk_mail:update_profile:#{Time.zone.today.year}", regular.id.to_s)

    sent = send_emails

    expect(sent).not_to include(regular.email)
    expect(sent).to include(other.email)
  end
end
