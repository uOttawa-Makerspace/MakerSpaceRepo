# frozen_string_literal: true

require "rails_helper"
require "rake"

# Mass mail keeps the legacy dormancy exclusion (User.active, deferred) and never reaches a deactivated user.
RSpec.describe "bulk mail rake tasks skip deactivated users" do
  let!(:regular) { create(:user, :regular_user) }
  let!(:dormant) { create(:user, :regular_user).tap { |u| User.where(id: u.id).update_all(active: false) } }
  let!(:deactivated) { create(:user, :regular_user).tap(&:deactivate!) }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("update_profile:send_emails")
    ActionMailer::Base.deliveries.clear
  end

  it "update_profile:send_emails BCCs only active, not deactivated users" do
    Rake::Task["update_profile:send_emails"].reenable
    sent = []
    allow(MsrMailer).to receive(:send_profile_update) { |list| sent.concat(list); instance_double(ActionMailer::MessageDelivery, deliver_now: true) }

    Rake::Task["update_profile:send_emails"].invoke("nobody@example.test")

    expect(sent).to include(regular.email)
    expect(sent).not_to include(deactivated.email, dormant.email)
  end

  it "emails:send_survey_ceed mails only active, not deactivated users" do
    Rake::Task["emails:send_survey_ceed"].reenable
    sent = []
    without_partial_double_verification do # the mailer action is commented out in MsrMailer
      allow(MsrMailer).to receive(:send_survey_ceed) { |email| sent << email; double(deliver_now: true) }
    end

    Rake::Task["emails:send_survey_ceed"].invoke

    expect(sent).to include(regular.email)
    expect(sent).not_to include(deactivated.email, dormant.email)
  end
end
