# frozen_string_literal: true

require "rails_helper"

# End-to-end volunteer journey: staff assign a volunteer to a task in the task
# editor, the volunteer submits the task as complete, staff approve the request
# and the volunteer gets the CC credit and the logged hours.
RSpec.describe "Journey: volunteer task", type: :system do
  let!(:volunteer) { create(:user, :volunteer_with_volunteer_program) }
  let!(:staff) { create(:user, :staff) }
  let!(:task) { create(:volunteer_task, title: "stocktake", cc: 10, hours: 5.0, joins: 1, user_id: staff.id) }

  before do
    allow_any_instance_of(Octokit::Client).to receive(:login).and_raise(Octokit::Unauthorized)
    ActionMailer::Base.deliveries.clear
  end

  it "staff assign -> volunteer submits completion -> staff approve -> CC and hours credited" do
    as_actor(:staff) do
      log_in_as(staff)
      visit edit_volunteer_task_path(task)
      expect(page).to have_css("h1", text: "Edit Volunteer Task")
      select volunteer.name, from: "volunteer_id"
      find("button[type=submit].btn-lg").click
      expect(page).to have_text("Volunteer task updated")
    end
    join = VolunteerTaskJoin.find_by!(volunteer_task: task, user: volunteer)
    expect(join.active).to be(true)
    expect(join.user_type).to eq("Volunteer")

    as_actor(:volunteer) do
      log_in_as(volunteer)
      visit volunteer_task_path(task)
      expect(page).to have_text("You are assigned to this volunteer task!")
      click_link "Submit Task as Complete"
      expect(page).to have_text("You've sent a request. No further action is needed.")
    end
    request = VolunteerTaskRequest.find_by!(volunteer_task: task, user: volunteer)
    expect(request.approval).to be_nil
    req_mail = deliver_mail.find { |m| m.subject == "New Request for task: Stocktake" }
    expect(req_mail.to).to eq([volunteer.email])

    as_actor(:staff) do
      visit volunteer_task_requests_path
      expect(page).to have_text(/stocktake/i)
      click_button "Approve"
      expect(page).to have_text("Task request updated")
    end
    expect(request.reload.approval).to be(true)
    expect(CcMoney.where(user: volunteer).sum(:cc)).to eq(10)
    expect(VolunteerHour.where(user: volunteer, volunteer_task: task).pluck(:total_time, :approval)).to eq([[5.0, true]])
    updated = deliver_mail.find { |m| m.subject == "Your request was updated: Stocktake" }
    expect(updated.to).to eq([volunteer.email])

    # WART(D-E2E06): VolunteerHour.create_volunteer_hour_from_approval leaves
    # date_of_task NULL, and volunteer_hours/index.html.erb:42 calls strftime on
    # it, so the volunteer's hours page 500s once any task approval exists.
    as_actor(:volunteer, allow_console: [%r{/volunteer_hours - Failed to load resource: .* 500}]) do
      visit volunteer_hours_path
      expect(page).to have_text("NoMethodError in VolunteerHours#index")
      expect(page).to have_text("undefined method 'strftime' for nil")
    end
    expect(VolunteerHour.find_by(user: volunteer).date_of_task).to be_nil
  end
end
