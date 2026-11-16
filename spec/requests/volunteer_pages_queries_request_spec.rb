# frozen_string_literal: true

require "rails_helper"

# Pages that list several volunteer rows load what each row shows together with the rows
# (under CI=1 Bullet fails a page that queries once per row).
RSpec.describe "Volunteer pages with several rows", type: :request do
  let(:makerspace) { create(:space, name: "Makerspace") }
  let(:brunsfield) { create(:space, name: "Brunsfield Centre") }
  let(:staff) { create(:user, :staff) }
  let(:volunteers) { create_list(:user, 2, :volunteer_with_volunteer_program) }
  let(:tasks) do
    [makerspace, brunsfield, makerspace].map { |space| create(:volunteer_task, space: space) }
  end

  before do
    tasks.each do |task|
      volunteers.each do |volunteer|
        VolunteerTaskJoin.create!(volunteer_task: task, user: volunteer, user_type: "Volunteer", state: "joined", active: true)
      end
    end
  end

  it "lists pending and processed hour requests" do
    tasks.each_with_index do |task, i|
      volunteers.each do |volunteer|
        create(:volunteer_hour, user: volunteer, volunteer_task: task, total_time: 1 + i, approval: nil)
        create(:volunteer_hour, user: volunteer, volunteer_task: task, total_time: 5 + i, approval: true)
      end
    end
    vol_login!(staff)

    get volunteer_hour_requests_volunteer_hours_path
    expect(response).to have_http_status(:ok)
    expect(response.body.scan("visit-button").size).to eq(12)
  end

  it "lists every scheduled shadowing shift for staff" do
    [staff, *volunteers].each_with_index do |user, i|
      [makerspace, brunsfield].each_with_index do |space, j|
        start = Time.current.change(min: 0) + (i * 2 + j + 1).days
        ShadowingHour.create!(user: user, space: space, start_time: start, end_time: start + 3.hours, event_id: "e#{i}#{j}")
      end
    end
    vol_login!(staff)

    get shadowing_shifts_volunteers_path
    expect(response).to have_http_status(:ok)
    expect(response.body.scan("fa-trash-can").size).to eq(8)
  end

  it "lists only the shadowing shifts that have both a start and an end time" do
    start = Time.zone.local(2030, 1, 7, 9)
    ShadowingHour.create!(user: staff, space: makerspace, start_time: start, end_time: start + 3.hours, event_id: "full")
    # Older rows can be stored without one of the times.
    ShadowingHour.create!(user: staff, space: makerspace, start_time: start + 1.day, end_time: start + 25.hours, event_id: "no-end")
                 .update_columns(end_time: nil)
    ShadowingHour.create!(user: staff, space: makerspace, start_time: start + 2.days, end_time: start + 50.hours, event_id: "no-start")
                 .update_columns(start_time: nil)
    vol_login!(staff)

    get shadowing_shifts_volunteers_path
    expect(response).to have_http_status(:ok)
    expect(response.body.scan("Monday, January 07, 2030").size).to eq(2)
    expect(response.body).to include("9:00 AM", "12:00 PM", "about 3 hours")
    expect(response.body).not_to include("event_id=no-end", "event_id=no-start")
  end

  it "lists a volunteer's tasks in progress and completed" do
    volunteer = volunteers.first
    create(:volunteer_task_request, volunteer_task: tasks.first, user: volunteer, approval: nil)
    create(:volunteer_task_request, volunteer_task: tasks.second, user: volunteer, approval: true)
    create(:volunteer_task_request, volunteer_task: tasks.third, user: volunteer, approval: true)
    done = create(:volunteer_task, space: brunsfield, status: "completed")
    VolunteerTaskJoin.create!(volunteer_task: done, user: volunteer, user_type: "Volunteer", state: "joined", active: true)
    vol_login!(volunteer)

    get my_tasks_volunteer_tasks_path
    expect(response).to have_http_status(:ok)
    expect(response.body.scan("<span>Under Review</span>").size).to eq(1)
    expect(response.body.scan("<span>Submit Complete</span>").size).to eq(2)
  end
end
