# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "confirmed_users:remind" do
  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("confirmed_users:remind")
    Rake::Task["confirmed_users:remind"].reenable
    ActionMailer::Base.deliveries.clear
  end

  it "mails unconfirmed users a confirmation link that the confirm action accepts (D-I11)" do
    unconfirmed = create(:user, :regular_user_not_confirmed)
    create(:user, :regular_user)

    Rake::Task["confirmed_users:remind"].invoke

    mails = ActionMailer::Base.deliveries
    expect(mails.map(&:to)).to eq([[unconfirmed.email]])
    token = CGI.unescape(mails.first.body.to_s[/confirm\?token=([^"'&\s<]+)/, 1])
    expect(User.find_by_token_for(:email_confirmation, token)).to eq(unconfirmed)
  end
end
