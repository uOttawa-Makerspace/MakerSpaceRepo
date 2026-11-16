# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "volunteer_awards:duplicates" do
  let(:user) { create(:user) }
  let(:task) { create(:volunteer_task) }

  before do
    Rails.application.load_tasks unless Rake::Task.task_defined?("volunteer_awards:duplicates")
    Rake::Task["volunteer_awards:duplicates"].reenable
  end

  it "says so when no award is held twice" do
    create(:cc_money, user: user, volunteer_task: task, cc: 5)
    create(:cc_money, user: create(:user), volunteer_task: task, cc: 5)
    create(:cc_money, user: user, volunteer_task: nil, cc: 5)
    create(:cc_money, user: user, volunteer_task: nil, cc: 5)

    expect { Rake::Task["volunteer_awards:duplicates"].invoke }.to output(/No user holds a task award more than once/).to_stdout
  end

  it "lists the ids of an award held twice and changes no row" do
    rows = [create(:cc_money, user: user, volunteer_task: task, cc: 5),
            create(:cc_money, user: user, volunteer_task: task, cc: 5, legacy_duplicate: true)]
    before = CcMoney.order(:id).pluck(:id, :cc, :user_id, :volunteer_task_id)

    expect { Rake::Task["volunteer_awards:duplicates"].invoke }
      .to output(/1 user and task pair\(s\).*user_id=#{user.id} volunteer_task_id=#{task.id} cc_money ids=#{rows.map(&:id).join(",")}/m).to_stdout

    expect(CcMoney.order(:id).pluck(:id, :cc, :user_id, :volunteer_task_id)).to eq(before)
  end
end
