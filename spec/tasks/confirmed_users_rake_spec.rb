# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "confirmed_users:remind" do
  include ActiveSupport::Testing::TimeHelpers

  let!(:unconfirmed) { create(:user, :regular_user_not_confirmed) }
  let!(:confirmed) { create(:user, :regular_user) }

  def remind(force: false)
    Rake::Task["confirmed_users:remind"].reenable
    ENV["FORCE"] = "1" if force
    ActionMailer::Base.deliveries.clear
    perform_enqueued_jobs { Rake::Task["confirmed_users:remind"].invoke }
    ActionMailer::Base.deliveries.flat_map(&:to)
  ensure
    ENV.delete("FORCE")
  end

  before { Rails.application.load_tasks unless Rake::Task.task_defined?("confirmed_users:remind") }

  it "mails unconfirmed users a confirmation link that the confirm action accepts" do
    remind

    mail = ActionMailer::Base.deliveries.first
    expect(mail.to).to eq([unconfirmed.email])
    token = CGI.unescape(mail.body.to_s[/confirm\?token=([^"'&\s<]+)/, 1])
    expect(User.find_by_token_for(:email_confirmation, token)).to eq(unconfirmed)
  end

  it "does not remind a deactivated user" do
    create(:user, :regular_user_not_confirmed).deactivate!

    expect(remind).to eq([unconfirmed.email])
  end

  it "mails nobody on a second run the same day" do
    remind
    expect(remind).to be_empty
  end

  it "mails everyone again when forced" do
    remind
    expect(remind(force: true)).to eq([unconfirmed.email])
  end

  it "mails again on the next day" do
    remind
    travel_to(1.day.from_now) { expect(remind).to eq([unconfirmed.email]) }
  end

  it "skips users already handled when a run was interrupted" do
    later = create(:user, :regular_user_not_confirmed)
    Setting.set("bulk_mail:confirmed_users_remind:#{Time.zone.today.iso8601}", unconfirmed.id.to_s)

    expect(remind).to eq([later.email])
  end

  it "repeats only the users from the one whose mail failed when a run is interrupted" do
    second = create(:user, :regular_user_not_confirmed)
    third = create(:user, :regular_user_not_confirmed)
    allow(MsrMailer).to receive(:confirmation_email).and_wrap_original do |original, user, hash|
      raise "mail down" if user == second
      original.call(user, hash)
    end
    ActionMailer::Base.deliveries.clear
    Rake::Task["confirmed_users:remind"].reenable
    expect { Rake::Task["confirmed_users:remind"].invoke }.to raise_error("mail down")
    expect(ActionMailer::Base.deliveries.flat_map(&:to)).to eq([unconfirmed.email])
    allow(MsrMailer).to receive(:confirmation_email).and_call_original

    expect(remind).to eq([second.email, third.email])
  end
end
