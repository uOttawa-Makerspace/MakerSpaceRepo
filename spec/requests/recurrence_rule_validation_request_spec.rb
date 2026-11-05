# frozen_string_literal: true

require "rails_helper"

# the server refuses sub-daily (and unparseable) recurrence rules for
# events and staff unavailabilities, and still accepts every rule the forms build.
RSpec.describe "Recurrence rule validation", type: :request do
  include SpacesSpecHelpers

  RRV_MINUTELY = "DTSTART:20270301T150000Z\nRRULE:FREQ=MINUTELY"
  # what rrule.js produces for each dropdown option (Daily/Weekly/Monthly) with BYDAY, UNTIL and COUNT
  RRV_FORM_RULES = [
    "DTSTART:20270301T150000Z\nRRULE:FREQ=DAILY",
    "DTSTART:20270301T150000Z\nRRULE:FREQ=DAILY;UNTIL=20270331T235959Z",
    "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE",
    "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;UNTIL=20270331T235959Z;BYDAY=MO",
    "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;COUNT=4;BYDAY=MO",
    "DTSTART:20270301T150000Z\nRRULE:FREQ=MONTHLY",
    "DTSTART:20270301T150000Z\nRRULE:FREQ=MONTHLY;UNTIL=20271231T235959Z;BYDAY=MO",
    "DTSTART:20270301T150000Z\nRRULE:FREQ=MONTHLY;COUNT=6"
  ].freeze
  RRV_REFUSED = [RRV_MINUTELY, "FREQ=SECONDLY", "RRULE:FREQ=HOURLY;COUNT=3", "garbage", "COUNT=3"].freeze

  describe "admin events" do
    let(:space) { create(:space) }
    let(:admin) { create(:user, :admin, booking_approval: true) }
    before { log_in!(admin) }

    def event_attrs(overrides = {})
      { event_type: "meeting", title: "Titled", description: "Desc", space_id: space.id,
        utc_start_time: "2027-03-01 15:00", utc_end_time: "2027-03-01 16:00" }.merge(overrides)
    end

    RRV_REFUSED.each do |rule|
      it "create refuses #{rule.inspect} and saves nothing" do
        expect { post admin_events_path, params: { event: event_attrs(recurrence_rule: rule) } }.not_to change(Event, :count)
        expect(flash[:alert]).to start_with("Failed to create event: Recurrence rule ")
        expect(flash[:notice]).to be_nil
      end
    end

    it "update refuses a sub-daily rule and keeps the record" do
      event = create(:event, space: space, title: "Keep")
      patch admin_event_path(event), params: { event: event_attrs(title: "Changed", recurrence_rule: RRV_MINUTELY) }
      expect(flash[:alert]).to start_with("Failed to update event: Recurrence rule must repeat daily")
      expect(event.reload).to have_attributes(title: "Keep", recurrence_rule: nil)
    end

    it "update scope 'all' refuses a sub-daily rule on a series" do
      series = create(:event, space: space, title: "Series", recurrence_rule: "DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO",
                              start_time: Time.utc(2027, 3, 1, 15), end_time: Time.utc(2027, 3, 1, 16))
      patch admin_event_path(series), params: { event: event_attrs(recurrence_rule: RRV_MINUTELY), update_scope: "all" }
      expect(flash[:alert]).to start_with("Failed to update event: Recurrence rule must repeat daily")
      expect(series.reload.recurrence_rule).to eq("DTSTART:20270301T150000Z\nRRULE:FREQ=WEEKLY;BYDAY=MO")
    end

    RRV_FORM_RULES.each do |rule|
      it "create accepts #{rule.inspect}" do
        expect { post admin_events_path, params: { event: event_attrs(recurrence_rule: rule) } }.to change(Event, :count).by(1)
        expect(flash[:notice]).to eq("Event created successfully.")
        expect(Event.order(:id).last.recurrence_rule).to eq(rule)
      end
    end

    it "update accepts a form rule" do
      event = create(:event, space: space)
      patch admin_event_path(event), params: { event: event_attrs(recurrence_rule: RRV_FORM_RULES[4]) }
      expect(flash[:notice]).to eq("Event updated successfully.")
      expect(event.reload.recurrence_rule).to eq(RRV_FORM_RULES[4])
    end

    context "a series stored with a sub-daily rule stored before validation existed" do
      let!(:legacy) do
        create(:event, space: space, title: "Legacy", start_time: Time.utc(2027, 3, 1, 15), end_time: Time.utc(2027, 3, 1, 16))
          .tap { |e| e.update_column(:recurrence_rule, RRV_MINUTELY) }
      end

      it "shows the validation error on edit and creates nothing for scope 'this'" do
        expect do
          patch admin_event_path(legacy), params: { event: event_attrs(title: "Once"), update_scope: "this" }
        end.not_to change(Event, :count)
        expect(flash[:alert]).to start_with("Failed to update event: Recurrence rule must repeat daily")
        expect(legacy.reload.recurrence_rule).to eq(RRV_MINUTELY)
      end

      it "shows the error on edit with scope 'all'" do
        patch admin_event_path(legacy), params: { event: event_attrs(title: "X", recurrence_rule: RRV_MINUTELY), update_scope: "all" }
        expect(flash[:alert]).to start_with("Failed to update event: Recurrence rule must repeat daily")
      end

      it "shows the error instead of a 500 when deleting a single occurrence" do
        delete delete_with_scope_admin_event_path(legacy), params: { scope: "single", start_date: "2027-03-02T15:00:00Z" }
        expect(flash[:alert]).to start_with("Failed to update event: Recurrence rule must repeat daily")
      end

      it "can still delete the whole series" do
        expect { delete delete_with_scope_admin_event_path(legacy), params: { scope: "all" } }.to change(Event, :count).by(-1)
      end
    end
  end

  describe "staff unavailabilities" do
    let!(:staff) { sign_in_as(:staff) }

    def payload(overrides = {})
      { staff_unavailability: { title: "Class", description: "desc",
                                utc_start_time: "2027-03-01T15:00:00Z", utc_end_time: "2027-03-01T16:00:00Z" }.merge(overrides) }
    end

    RRV_REFUSED.each do |rule|
      it "create refuses #{rule.inspect} and saves nothing" do
        expect { post staff_unavailabilities_path, params: payload(recurrence_rule: rule) }.not_to change(StaffUnavailability, :count)
        expect(flash[:alert]).to start_with("Failed to create unavailability: Recurrence rule ")
      end
    end

    it "update refuses a sub-daily rule and keeps the record" do
      record = create(:staff_unavailability, user: staff, title: "Keep")
      patch staff_unavailability_path(record), params: payload(title: "Changed", recurrence_rule: RRV_MINUTELY)
      expect(flash[:alert]).to start_with("Failed to update unavailability: Recurrence rule must repeat daily")
      expect(record.reload).to have_attributes(title: "Keep", recurrence_rule: nil)
    end

    RRV_FORM_RULES.each do |rule|
      it "create accepts #{rule.inspect}" do
        expect { post staff_unavailabilities_path, params: payload(recurrence_rule: rule) }.to change(StaffUnavailability, :count).by(1)
        expect(StaffUnavailability.order(:id).last.recurrence_rule).to eq(rule)
      end
    end

    it "update accepts a form rule" do
      record = create(:staff_unavailability, user: staff)
      patch staff_unavailability_path(record), params: payload(recurrence_rule: RRV_FORM_RULES[2])
      expect(flash[:notice]).to eq("Unavailability updated successfully.")
      expect(record.reload.recurrence_rule).to eq(RRV_FORM_RULES[2])
    end

    context "a series stored with a sub-daily rule stored before validation existed" do
      let!(:legacy) do
        create(:staff_unavailability, user: staff, start_time: Time.utc(2027, 3, 1, 15), end_time: Time.utc(2027, 3, 1, 16))
          .tap { |r| r.update_column(:recurrence_rule, RRV_MINUTELY) }
      end

      it "shows the error for scope 'this' and creates nothing" do
        expect do
          patch staff_unavailability_path(legacy), params: payload(title: "Once").merge(update_scope: "this")
        end.not_to change(StaffUnavailability, :count)
        expect(flash[:alert]).to start_with("Failed to update unavailability: Recurrence rule must repeat daily")
      end

      it "shows the error instead of a 500 when deleting a single occurrence" do
        delete delete_with_scope_staff_unavailability_path(legacy), params: { scope: "single", start_date: "2027-03-02T15:00:00Z" }
        expect(response).to redirect_to(staff_unavailabilities_path)
        expect(flash[:alert]).to start_with("Failed to update unavailability: Recurrence rule must repeat daily")
      end
    end
  end
end
