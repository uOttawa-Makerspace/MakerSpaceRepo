# frozen_string_literal: true

require "rails_helper"

# Characterization of Admin::SpacesController (chunk 14).
# AdminAreaController#ensure_admin sends every non-admin (guest included:
# current_user is User.new, never nil) to "/" with no flash. Redirects use
# redirect_back, so without a Referer they land on root_path.

RSpec.describe "Admin spaces", type: :request do
  include SpacesSpecHelpers

  before { seed_booking_statuses! }

  let!(:space) { create(:space, name: "Alpha") }
  let!(:room) { create(:sub_space, space: space, name: "Room A") }

  def snapshot
    [Space.count, SubSpace.count, space.reload.attributes, room.reload.attributes,
     SpaceManagerJoin.count, StaffNeededCalendar.count, SubSpaceBooking.count]
  end

  describe "role matrix" do
    let(:calls) do
      {
        index: -> { get admin_spaces_path },
        edit: -> { get edit_admin_space_path(space) },
        create: -> { post admin_spaces_path, params: { space_params: { name: "Nope" } } },
        create_sub_space: -> { put admin_space_create_sub_space_path(space_id: space.id), params: { name: "Nope" } },
        delete_sub_space: -> { delete admin_space_delete_sub_space_path(space_id: space.id, id: room.id) },
        approval: -> { put admin_space_change_sub_space_approval_path(space_id: space.id, id: room.id) },
        default_public: -> { post admin_space_change_sub_space_default_public_path(space_id: space.id, id: room.id) },
        rename_sub: -> { patch admin_space_update_sub_space_path(space_id: space.id, id: room.id), params: { name: "Nope" } },
        max_duration: -> { patch admin_space_set_max_booking_duration_path(space_id: space.id, sub_space_id: room.id), params: { max_hours: 3 } },
        max_auto: -> { patch admin_space_set_max_automatic_approval_hour_path(space_id: space.id, sub_space_id: room.id), params: { auto_approve_hours: 3 } },
        update_name: -> { post admin_space_update_name_path(space_id: space.id), params: { name: "Nope" } },
        capacity: -> { post update_max_capacity_admin_spaces_path, params: { space_id: space.id, max_capacity: 9 } },
        keycode: -> { patch update_keycode_admin_spaces_path, params: { space_id: space.id, keycode: "Nope" } },
        add_manager: -> { patch add_space_manager_admin_spaces_path, params: { space_id: space.id, space_manager_id: create(:user, :admin).id } },
        remove_manager: -> { patch remove_space_manager_admin_spaces_path, params: { space_manager_join_id: 0 } },
        destroy: -> { delete admin_space_destroy_path(space_id: space.id), params: { id: space.id, admin_input: "ALPHA" } },
        calendars: -> { put update_staff_needed_calendars_admin_spaces_path, params: { space_id: space.id, staff_needed_calendar: ["https://x.test/a.ics"] } }
      }
    end

    %i[guest regular staff].each do |role|
      it "bounces #{role} to / on every action and changes nothing" do
        sign_in_as(role)
        calls.each do |name, call|
          before_state = snapshot
          instance_exec(&call)
          expect(response).to redirect_to("/"), "#{name} as #{role}: #{response.status}"
          expect(flash.to_h).to eq({}), name.to_s
          expect(snapshot).to eq(before_state), name.to_s
        end
      end
    end
  end

  context "as admin" do
    let!(:admin) { sign_in_as(:admin) }

    it "lists spaces (index) and renders the edit page" do
      get admin_spaces_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alpha")
      get edit_admin_space_path(space)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Room A")
    end

    it "edit 404s for an unknown space" do
      get edit_admin_space_path(0)
      expect(response).to have_http_status(:not_found)
    end

    describe "create" do
      it "creates a space and redirects back with a notice" do
        expect {
          post admin_spaces_path, params: { space_params: { name: "Beta", max_capacity: 7, keycode: "k1" } }
        }.to change(Space, :count).by(1)
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Space created successfully!")
        expect(Space.find_by!(name: "Beta")).to have_attributes(max_capacity: 7, keycode: "k1")
      end

      it "alerts on a blank or duplicate name" do
        expect { post admin_spaces_path, params: { space_params: { name: "" } } }.not_to change(Space, :count)
        expect(flash[:alert]).to eq("Something went wrong.")
        expect { post admin_spaces_path, params: { space_params: { name: "Alpha" } } }.not_to change(Space, :count)
        expect(flash[:alert]).to eq("Something went wrong.")
      end

      it "redirects home with the ParameterMissing message when space_params is absent" do
        post admin_spaces_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to match(/space_params/)
      end
    end

    describe "sub spaces" do
      it "creates a sub space, with approval_required only when the param is '1'" do
        put admin_space_create_sub_space_path(space_id: space.id), params: { name: "Room B", approval_required: "1" }
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Sub Space created!")
        expect(SubSpace.find_by!(name: "Room B")).to have_attributes(space_id: space.id, approval_required: true, default_public: false)

        put admin_space_create_sub_space_path(space_id: space.id), params: { name: "Room C", approval_required: "0" }
        expect(SubSpace.find_by!(name: "Room C").approval_required).to be(false)
      end

      it "alerts when the name is blank and 404s for an unknown space" do
        expect {
          put admin_space_create_sub_space_path(space_id: space.id), params: { name: "" }
        }.not_to change(SubSpace, :count)
        expect(flash[:alert]).to eq("Please enter a name for the sub space")
        put admin_space_create_sub_space_path(space_id: 0), params: { name: "X" }
        expect(response).to have_http_status(:not_found)
      end

      it "renames, rejecting a blank name" do
        patch admin_space_update_sub_space_path(space_id: space.id, id: room.id), params: { name: "Room Z" }
        expect(response).to redirect_to(edit_admin_space_path(id: space.id, anchor: "sub_space_area"))
        expect(flash[:notice]).to eq("You've successfully renamed 'Room A' to 'Room Z'.")
        expect(room.reload.name).to eq("Room Z")

        patch admin_space_update_sub_space_path(space_id: space.id, id: room.id), params: { name: "" }
        expect(flash[:alert]).to eq("Sub Space name cannot be blank.")
        expect(room.reload.name).to eq("Room Z")
      end

      describe "approval toggle" do
        it "refuses to switch to automatic without space contact info" do
          put admin_space_change_sub_space_approval_path(space_id: space.id, id: room.id)
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq("Please add contact information for the associated space disabling automatic booking.")
          expect(room.reload.approval_required).to be(false)
        end

        it "toggles both ways when contact info exists" do
          create(:contact_info, space_id: space.id)
          put admin_space_change_sub_space_approval_path(space_id: space.id, id: room.id)
          expect(response).to redirect_to(edit_admin_space_path(id: space.id, anchor: "sub_space_area"))
          expect(flash[:notice]).to eq("Aproval for Room A is now manual")
          expect(room.reload.approval_required).to be(true)
          put admin_space_change_sub_space_approval_path(space_id: space.id, id: room.id)
          expect(flash[:notice]).to eq("Aproval for Room A is now automatic")
          expect(room.reload.approval_required).to be(false)
        end
      end

      # default_public feeds SubSpaceBookingController#create (booking.public)
      # and the index "rules" text; both pinned in the bookings specs.
      it "toggles default_public (false by default) with a flash naming the new default" do
        expect(room.default_public).to be(false)
        post admin_space_change_sub_space_default_public_path(space_id: space.id, id: room.id)
        expect(response).to redirect_to(edit_admin_space_path(id: space.id, anchor: "sub_space_area"))
        expect(flash[:notice]).to eq("Bookings in Room A are public by default")
        expect(room.reload.default_public).to be(true)
        post admin_space_change_sub_space_default_public_path(space_id: space.id, id: room.id)
        expect(flash[:notice]).to eq("Bookings in Room A are private by default")
        expect(room.reload.default_public).to be(false)
      end

      it "sets and clears max booking duration / weekly hours / automatic approval hours (-1 clears)" do
        patch admin_space_set_max_booking_duration_path(space_id: space.id, sub_space_id: room.id), params: { max_hours: 4 }
        expect(response).to redirect_to(edit_admin_space_path(id: space.id, anchor: "sub_space_area"))
        expect(flash[:notice]).to eq("Max booking duration updated!")
        expect(room.reload.maximum_booking_duration).to eq(4)
        patch admin_space_set_max_booking_duration_path(space_id: space.id, sub_space_id: room.id), params: { max_hours: -1 }
        expect(room.reload.maximum_booking_duration).to be_nil

        patch admin_space_set_max_booking_duration_path(space_id: space.id, sub_space_id: room.id), params: { max_weekly_hours: 10 }
        expect(flash[:notice]).to eq("Max weekly booking duration updated!")
        expect(room.reload.maximum_booking_hours_per_week).to eq(10)
        patch admin_space_set_max_booking_duration_path(space_id: space.id, sub_space_id: room.id), params: { max_weekly_hours: -1 }
        expect(room.reload.maximum_booking_hours_per_week).to be_nil

        patch admin_space_set_max_automatic_approval_hour_path(space_id: space.id, sub_space_id: room.id), params: { auto_approve_hours: 2 }
        expect(flash[:notice]).to eq("Max automatic approval duration updated!")
        expect(room.reload.max_automatic_approval_hour).to eq(2)
        patch admin_space_set_max_automatic_approval_hour_path(space_id: space.id, sub_space_id: room.id), params: { auto_approve_hours: -1 }
        expect(room.reload.max_automatic_approval_hour).to be_nil
      end

      it "alerts when the limit params are missing" do
        patch admin_space_set_max_booking_duration_path(space_id: space.id, sub_space_id: room.id)
        expect(response).to redirect_to(edit_admin_space_path(id: space.id))
        expect(flash[:alert]).to eq("Something went wrong.")
        patch admin_space_set_max_automatic_approval_hour_path(space_id: space.id, sub_space_id: room.id)
        expect(flash[:alert]).to eq("Something went wrong.")
      end

      # WART(D-SP02): a non-numeric limit is silently stored as 0 (to_i) rather than rejected.
      it "stores a non-numeric max_hours as 0" do
        patch admin_space_set_max_booking_duration_path(space_id: space.id, sub_space_id: room.id), params: { max_hours: "abc" }
        expect(room.reload.maximum_booking_duration).to eq(0)
      end

      it "delete_sub_space removes the room together with its bookings and statuses" do
        booking = create(:sub_space_booking, sub_space: room)
        status_id = booking.sub_space_booking_status_id
        delete admin_space_delete_sub_space_path(space_id: space.id, id: room.id)
        expect(response).to redirect_to(edit_admin_space_path(id: space.id))
        expect(flash[:notice]).to eq("Sub Space deleted!")
        expect(SubSpace.exists?(room.id)).to be(false)
        expect(SubSpaceBooking.exists?(booking.id)).to be(false)
        expect(SubSpaceBookingStatus.exists?(status_id)).to be(false)
      end

      # WART(D-B50): delete_sub_space raises (404) for a booking with a nil status id and deletes nothing.
      it "delete_sub_space 404s and keeps the room when a booking has no status (D-B50)" do
        booking = create(:sub_space_booking, sub_space: room)
        booking.update_column(:sub_space_booking_status_id, nil)
        delete admin_space_delete_sub_space_path(space_id: space.id, id: room.id)
        expect(response).to have_http_status(:not_found)
        expect(SubSpace.exists?(room.id)).to be(true)
        expect(SubSpaceBooking.exists?(booking.id)).to be(true)
      end
    end

    describe "space attributes" do
      it "update_name renames and redirects back" do
        post admin_space_update_name_path(space_id: space.id), params: { name: "Gamma" }
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Space Name updated !")
        expect(space.reload.name).to eq("Gamma")
      end

      # WART(D-SP03): update_name with an invalid (blank/duplicate) name renders nothing: 204, no flash.
      it "update_name answers 204 with no flash on a blank or duplicate name" do
        create(:space, name: "Taken")
        [ "", "Taken" ].each do |bad|
          post admin_space_update_name_path(space_id: space.id), params: { name: bad }
          expect(response).to have_http_status(:no_content)
          expect(flash.to_h).to eq({})
          expect(space.reload.name).to eq("Alpha")
        end
      end

      # WART(D-SP04): update_max_capacity computes nil-for-zero then ignores it; "0" is stored as 0, not "no limit".
      it "update_max_capacity stores the raw value (0 is not turned into nil)" do
        post update_max_capacity_admin_spaces_path, params: { space_id: space.id, max_capacity: "12" }
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Space Capacity updated!")
        expect(space.reload.max_capacity).to eq(12)
        post update_max_capacity_admin_spaces_path, params: { space_id: space.id, max_capacity: "0" }
        expect(space.reload.max_capacity).to eq(0)
      end

      it "update_keycode saves any string" do
        patch update_keycode_admin_spaces_path, params: { space_id: space.id, keycode: "9999" }
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Space keycode updated!")
        expect(space.reload.keycode).to eq("9999")
      end
    end

    describe "space managers" do
      let(:manager) { create(:user, :admin) }

      it "adds an admin as manager and redirects to the index" do
        patch add_space_manager_admin_spaces_path, params: { space_id: space.id, space_manager_id: manager.id }
        expect(response).to redirect_to(admin_spaces_path)
        expect(flash[:notice]).to eq("Successfully added space manager")
        expect(space.reload.space_managers).to eq([manager])
      end

      it "refuses non-admins, duplicates and the -1 placeholder" do
        patch add_space_manager_admin_spaces_path, params: { space_id: space.id, space_manager_id: create(:user, :staff).id }
        expect(response).to redirect_to(admin_spaces_path)
        expect(flash[:alert]).to eq("Failed to add space manager")
        SpaceManagerJoin.create!(user: manager, space: space)
        patch add_space_manager_admin_spaces_path, params: { space_id: space.id, space_manager_id: manager.id }
        expect(flash[:alert]).to eq("Failed to add space manager")
        patch add_space_manager_admin_spaces_path, params: { space_id: space.id, space_manager_id: -1 }
        expect(flash[:alert]).to eq("Please select an admin")
        expect(SpaceManagerJoin.count).to eq(1)
      end

      it "removes a manager, or alerts when the join is unknown" do
        join = SpaceManagerJoin.create!(user: manager, space: space)
        patch remove_space_manager_admin_spaces_path, params: { space_manager_join_id: join.id }
        expect(response).to redirect_to(admin_spaces_path)
        expect(flash[:notice]).to eq("Successfully removed space manager")
        expect(SpaceManagerJoin.exists?(join.id)).to be(false)
        patch remove_space_manager_admin_spaces_path, params: { space_manager_join_id: join.id }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("Cannot find space manager")
      end
    end

    describe "destroy (two-admin approval)" do
      # The route is DELETE /admin/spaces/:space_id/edit but the action reads params[:id].
      def destroy_space(input, id: space.id)
        delete admin_space_destroy_path(space_id: space.id), params: { id: id, admin_input: input }
      end

      it "rejects wrong confirmation text" do
        destroy_space("alpha")
        expect(response).to redirect_to(admin_spaces_path)
        expect(flash[:alert]).to eq("Invalid Input")
        expect(space.reload.destroy_admin_id).to be_nil
      end

      it "first admin only records a destroy request; a second admin destroys and detaches pi readers" do
        reader = create(:pi_reader, space: space)
        destroy_space("ALPHA")
        expect(response).to redirect_to(admin_spaces_path)
        expect(flash[:notice]).to eq("The destroy request has been submitted, a second admin will need to approve it for the space to be destroyed.")
        expect(space.reload.destroy_admin_id).to eq(admin.id)

        destroy_space("ALPHA") # same admin again: just re-records the request
        expect(Space.exists?(space.id)).to be(true)

        second = sign_in_as(:admin)
        expect { destroy_space("ALPHA") }.to change(Space, :count).by(-1)
        expect(flash[:notice]).to eq("Space deleted!")
        expect(reader.reload.space_id).to be_nil
        expect(second).to be_present
      end

      it "404s without the id param (the route only supplies space_id)" do
        delete admin_space_destroy_path(space_id: space.id), params: { admin_input: "ALPHA" }
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "update_staff_needed_calendars" do
      let(:url) { "https://cal.test/a.ics" }

      def save_calendars(space_id: space.id, **extra)
        put update_staff_needed_calendars_admin_spaces_path, params: { space_id: space_id }.merge(extra)
      end

      it "alerts when space_id is missing" do
        put update_staff_needed_calendars_admin_spaces_path
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq("An error occurred while trying to add/remove the calendar URLs, please try again later.")
      end

      it "replaces all calendars (new rows each save), skipping blank urls and blank roles" do
        old = StaffNeededCalendar.create!(space: space, calendar_url: "https://old.test/x.ics")
        save_calendars(staff_needed_calendar: [url, ""], staff_needed_calendar_name: ["Cal", "Blank"],
                       staff_needed_calendar_color: ["#112233", "#000000"], staff_needed_calendar_role: ["", "x"])
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Calendars updated successfully.")
        expect(StaffNeededCalendar.exists?(old.id)).to be(false)
        expect(StaffNeededCalendar.where(space: space).count).to eq(1)
        expect(StaffNeededCalendar.last).to have_attributes(calendar_url: url, name: "Cal", color: "#112233", role: nil)
      end

      it "clears everything when saved with no urls" do
        StaffNeededCalendar.create!(space: space, calendar_url: "https://old.test/x.ics")
        save_calendars
        expect(StaffNeededCalendar.where(space: space)).to be_empty
        expect(flash[:notice]).to eq("Calendars updated successfully.")
      end

      # WART(D-SP25): a calendar with an unknown role fails validation, is silently dropped (create, not create!), and the save still reports success.
      it "silently drops a calendar with an invalid role but flashes success" do
        save_calendars(staff_needed_calendar: [url], staff_needed_calendar_role: ["bogus"])
        expect(flash[:notice]).to eq("Calendars updated successfully.")
        expect(StaffNeededCalendar.where(space: space)).to be_empty
      end

      it "allows only one open_hours calendar and keeps existing rows when refused" do
        keep = StaffNeededCalendar.create!(space: space, calendar_url: "https://old.test/x.ics")
        save_calendars(staff_needed_calendar: [url, "https://cal.test/b.ics"],
                       staff_needed_calendar_role: %w[open_hours open_hours])
        expect(flash[:alert]).to eq("Only one calendar can be assigned the 'open_hours' role.")
        expect(StaffNeededCalendar.where(space: space)).to eq([keep])
      end

      it "500s (FK violation) for an unknown space id and stores nothing" do
        save_calendars(space_id: 0, staff_needed_calendar: [url])
        expect(response).to have_http_status(:internal_server_error)
        expect(StaffNeededCalendar.count).to eq(0)
      end

      describe "makeroom ICS import" do
        before do
          stub_ics(url, body: ics_document(uid: "u1", summary: "Booked", start: 2.days.from_now, end: 2.days.from_now + 1.hour,
                                           location: "Room A", description: "d"))
        end

        def save_makeroom
          save_calendars(staff_needed_calendar: [url], staff_needed_calendar_name: ["Cal"],
                         staff_needed_calendar_color: ["#fff"], staff_needed_calendar_role: ["makeroom"])
        end

        it "fetches the feed over HTTP and stores the calendar with role makeroom" do
          save_makeroom
          expect(a_request(:get, url)).to have_been_made.once
          expect(StaffNeededCalendar.last).to have_attributes(role: "makeroom", name: "Cal", space_id: space.id)
        end

        # WART(D-SP01): the import matches event[:extendedProps][:location], which parse_ics_calendar never sets, so no booking is ever created.
        # D-B49 (duplicate pending blocking bookings on every save) is therefore unreachable today:
        # saving twice still yields zero bookings. Pinned so a fix that wires location through is noticed.
        it "creates no bookings even for an event whose LOCATION equals a sub space name (D-B49, D-SP01)" do
          expect { save_makeroom }.not_to change(SubSpaceBooking, :count)
          expect { save_makeroom }.not_to change(SubSpaceBooking, :count)
          expect(SubSpaceBookingStatus.count).to eq(0)
          expect(flash[:notice]).to eq("Calendars updated successfully.")
          expect(StaffNeededCalendar.where(space: space).count).to eq(1) # re-created, not duplicated
        end

        # WART(D-SP05): a failing feed makes parse_ics_calendar return [], and the import does `@events[0][:events]` on nil: 500.
        # The calendar row has already been saved (no transaction), the response is not a redirect.
        it "500s when the feed is unreachable and the space has sub spaces (D-SP05)" do
          stub_ics(url, status: 500)
          expect { save_makeroom }.not_to change(SubSpaceBooking, :count)
          expect(response).to have_http_status(:internal_server_error)
          expect(StaffNeededCalendar.where(space: space, role: "makeroom").count).to eq(1)
        end
      end
    end
  end
end
