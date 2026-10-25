# frozen_string_literal: true

require "rails_helper"

# Chunk 13: the four MsrMailer volunteer-task emails, rendered directly.
# (Delivered-outcome pins through the controllers live in the request specs.)
RSpec.describe MsrMailer, "volunteer task emails", type: :mailer do
  let(:task) { create(:volunteer_task, title: "booth duty") }
  let(:volunteer) { create(:user, :volunteer_with_volunteer_program) }
  let(:staff) { create(:user, :staff) }

  it "send_notification_to_staff_for_joining_task goes to the staff user" do
    mail = MsrMailer.send_notification_to_staff_for_joining_task(task.id, volunteer.id, staff.id)
    expect(mail.to).to eq([staff.email])
    expect(mail.subject).to eq("New join in task: Booth duty")
    expect(mail.body.encoded).to include("Booth duty")
  end

  it "...falls back to volunteer@makerepo.com without a staff id" do
    expect(MsrMailer.send_notification_to_staff_for_joining_task(task.id, volunteer.id, nil).to).to eq(["volunteer@makerepo.com"])
  end

  it "send_notification_to_volunteer_for_joining_task goes to the volunteer" do
    mail = MsrMailer.send_notification_to_volunteer_for_joining_task(task.id, volunteer.id, staff.id)
    expect(mail.to).to eq([volunteer.email])
    expect(mail.subject).to eq("New join in task: Booth duty")
  end

  it "send_notification_for_task_request goes to the volunteer with volunteer@makerepo.com in bcc" do
    mail = MsrMailer.send_notification_for_task_request(task.id, volunteer.id)
    expect([mail.to, mail.bcc, mail.subject]).to eq([[volunteer.email], ["volunteer@makerepo.com"], "New Request for task: Booth duty"])
  end

  it "send_notification_for_task_request_update goes to the requester and links the requests page" do
    req = create(:volunteer_task_request, user: volunteer, volunteer_task: task)
    mail = MsrMailer.send_notification_for_task_request_update(req.id)
    expect([mail.to, mail.subject]).to eq([[volunteer.email], "Your request was updated: Booth duty"])
    expect(mail.body.encoded).to include("https://makerepo.com/volunteer_task_requests/")
  end

  it "raise RecordNotFound for unknown ids" do
    expect { MsrMailer.send_notification_for_task_request(task.id, 0).message }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
