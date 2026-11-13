# frozen_string_literal: true

require "rails_helper"

# Characterization of Admin::SpacesController (chunk 14).
# AdminAreaController#ensure_admin sends a guest to the login page and every
# other non-admin to "/" with no flash. Redirects use redirect_back, so without
# a Referer they land on root_path.

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
      it "bounces #{role} on every action and changes nothing" do
        sign_in_as(role)
        calls.each do |name, call|
          before_state = snapshot
          instance_exec(&call)
          expect_admin_area_bounce(guest: role == :guest)
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

    it "counts each training's sessions and active certifications, across spaces, without a query per session" do
      laser = create(:training, name_en: "Laser", spaces: [space])
      create(:training, name_en: "Mill", spaces: [space])
      sessions = [space, space, create(:space)].map { |where| create(:training_session, training: laser, space: where) }
      sessions.each_with_index { |ts, i| create_list(:certification, 2 - (i / 2), training_session: ts, training: laser) }
      sessions.first.certifications.first.update_columns(active: false)

      get edit_admin_space_path(space)

      expect(response).to have_http_status(:ok)
      rows = Nokogiri::HTML(response.body).css("table tr").map { |tr| tr.css("td").map { |td| td.text.strip } }
      expect(rows).to include(["Laser", "3", "4", ""], ["Mill", "0", "0", ""])
    end

    it "gives every calendar colour input its own id and an accessible name, keeping each saved colour" do
      StaffNeededCalendar.create!(space: space, calendar_url: "https://x.test/a.ics", color: "#112233")
      StaffNeededCalendar.create!(space: space, calendar_url: "https://x.test/b.ics", color: "#445566")

      get edit_admin_space_path(space)

      page = Nokogiri::HTML(response.body)
      inputs = page.css("#link-container input[type=color]")
      expect(inputs.map { |input| input["value"] }).to match_array(%w[#112233 #445566])
      expect(inputs.map { |input| input["id"] }.uniq.size).to eq(2)
      expect(page.css("input[type=color][id]").map { |input| input["id"] }).to all(start_with("staff_needed_calendar_color_"))
      expect(page.css("#colorpicker")).to be_empty
      expect(page.css("input[type=color]").map { |input| input["aria-label"] }).to all(be_present)
    end

    it "gives every calendar name, url and role input its own id and an accessible name, keeping the submitted names" do
      StaffNeededCalendar.create!(space: space, name: "A", calendar_url: "https://x.test/a.ics", color: "#112233")
      StaffNeededCalendar.create!(space: space, name: "B", calendar_url: "https://x.test/b.ics", color: "#445566")

      get edit_admin_space_path(space)

      page = Nokogiri::HTML(response.body)
      { "staff_needed_calendar_name[]" => "input", "staff_needed_calendar[]" => "input", "staff_needed_calendar_role[]" => "select" }.each do |name, tag|
        saved = page.css("#link-container #{tag}[name='#{name}']")
        expect(saved.map { |field| field["id"] }.uniq.size).to eq(2)
        expect(page.css("#{tag}[name='#{name}']").map { |field| field["aria-label"] }).to all(be_present)
        expect(page.css("#new-link-input #{tag}[name='#{name}']").map { |field| field["id"] }).to eq([nil])
      end
      ids = page.css("#link-container [id]").map { |node| node["id"] }
      expect(ids).to eq(ids.uniq)
    end

    it "gives every element on the page a unique id, with two sub spaces" do
      create(:sub_space, space: space, name: "Room B")

      get edit_admin_space_path(space)

      page = Nokogiri::HTML(response.body)
      ids = page.css("[id]").map { |node| node["id"] }
      expect(ids.tally.select { |_id, count| count > 1 }).to be_empty
      expect(page.css("input[type=hidden][name=space_id]").size).to be >= 5
      expect(page.css("input[name=name]").map { |input| input["aria-label"] }).to all(be_present)
    end

    it "gives the new calendar row a colour the colour input accepts" do
      get edit_admin_space_path(space)

      colour = Nokogiri::HTML(response.body).at_css("#new-link-input input[type=color]")["value"]
      expect(colour).to match(/\A#\h{6}\z/)
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

      it "creates the popular hour rows for the new space and none when the save fails" do
        expect {
          post admin_spaces_path, params: { space_params: { name: "Beta", max_capacity: 7, keycode: "k1" } }
        }.to change(PopularHour, :count).by(168)
        expect(Space.find_by!(name: "Beta").popular_hours.pluck(:day, :hour)).to match_array((0..6).to_a.product((0..23).to_a))

        expect { post admin_spaces_path, params: { space_params: { name: "Beta" } } }.not_to change(PopularHour, :count)
      end

      it "stores no space and shows the reason, not a server error, when the popular hour rows cannot be inserted" do
        allow(PopularHour).to receive(:insert_all).and_raise(ActiveRecord::StatementInvalid, "insert failed")
        expect {
          post admin_spaces_path, params: { space_params: { name: "Gamma", max_capacity: 7, keycode: "k9" } }
        }.not_to change { [Space.count, PopularHour.count] }
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to start_with("The space was not created. ").and include("popular hours")
        expect(Space.find_by(name: "Gamma")).to be_nil
      end

      it "alerts on a blank or duplicate name" do
        expect { post admin_spaces_path, params: { space_params: { name: "" } } }.not_to change(Space, :count)
        expect(flash[:alert]).to start_with("The space was not created. ")
        expect { post admin_spaces_path, params: { space_params: { name: "Alpha" } } }.not_to change(Space, :count)
        expect(flash[:alert]).to start_with("The space was not created. ")
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
        expect(flash[:alert]).to eq("Choose a sub space and enter the number of hours for the limit you want to change.")
        patch admin_space_set_max_automatic_approval_hour_path(space_id: space.id, sub_space_id: room.id)
        expect(flash[:alert]).to eq("Choose a sub space and enter the number of hours for the automatic approval limit.")
      end

      it "refuses a limit that is not a whole number of hours and keeps the stored limits" do
        room.update!(maximum_booking_duration: 3, maximum_booking_hours_per_week: 9, max_automatic_approval_hour: 1)
        ["abc", "2.5", "-2", "1e3"].each do |bad|
          patch admin_space_set_max_booking_duration_path(space_id: space.id, sub_space_id: room.id), params: { max_hours: bad }
          expect(response).to redirect_to(edit_admin_space_path(id: space.id))
          expect(flash[:alert]).to eq("The limit must be a whole number of hours, or -1 to remove it.")
          patch admin_space_set_max_booking_duration_path(space_id: space.id, sub_space_id: room.id), params: { max_weekly_hours: bad }
          expect(flash[:alert]).to eq("The limit must be a whole number of hours, or -1 to remove it.")
          patch admin_space_set_max_automatic_approval_hour_path(space_id: space.id, sub_space_id: room.id), params: { auto_approve_hours: bad }
          expect(flash[:alert]).to eq("The limit must be a whole number of hours, or -1 to remove it.")
        end
        expect(room.reload).to have_attributes(maximum_booking_duration: 3, maximum_booking_hours_per_week: 9, max_automatic_approval_hour: 1)
      end

      it "names the refused limit in French" do
        patch admin_space_set_max_booking_duration_path(space_id: space.id, sub_space_id: room.id), params: { max_hours: "abc", locale: "fr" }
        expect(flash[:alert]).to eq("La limite doit être un nombre entier d'heures, ou -1 pour la retirer.")
      end

      it "delete_sub_space refuses a room that has bookings and keeps the room, bookings and statuses" do
        booking = create(:sub_space_booking, :with_old_status_row, sub_space: room)
        status_id = booking.sub_space_booking_status_id
        delete admin_space_delete_sub_space_path(space_id: space.id, id: room.id)
        expect(response).to redirect_to(edit_admin_space_path(id: space.id))
        expect(flash[:alert]).to include("bookings")
        expect(flash[:notice]).to be_nil
        expect(SubSpace.exists?(room.id)).to be(true)
        expect(SubSpaceBooking.exists?(booking.id)).to be(true)
        expect(SubSpaceBookingStatus.exists?(status_id)).to be(true)
      end

      it "delete_sub_space removes a room that has no bookings" do
        delete admin_space_delete_sub_space_path(space_id: space.id, id: room.id)
        expect(flash[:notice]).to eq("Sub Space deleted!")
        expect(SubSpace.exists?(room.id)).to be(false)
      end
    end

    describe "space attributes" do
      it "update_name renames and redirects back" do
        post admin_space_update_name_path(space_id: space.id), params: { name: "Gamma" }
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Space Name updated !")
        expect(space.reload.name).to eq("Gamma")
      end

      it "update_name redirects back with the validation error on a blank or duplicate name" do
        create(:space, name: "Taken")
        { "" => "A name is required for the space", "Taken" => "A space with that name already exists" }.each do |bad, message|
          post admin_space_update_name_path(space_id: space.id), params: { name: bad }
          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq(message)
          expect(space.reload.name).to eq("Alpha")
        end
      end

      it "update_name gives the validation error in French" do
        create(:space, name: "Taken")
        post admin_space_update_name_path(space_id: space.id), params: { name: "Taken", locale: "fr" }
        expect(flash[:alert]).to eq("Un espace portant ce nom existe déjà")
      end

      it "update_max_capacity stores a positive number, and 0 or blank as no limit" do
        post update_max_capacity_admin_spaces_path, params: { space_id: space.id, max_capacity: "12" }
        expect(response).to redirect_to(root_path)
        expect(flash[:notice]).to eq("Space Capacity updated!")
        expect(space.reload.max_capacity).to eq(12)
        [ "0", "" ].each do |no_limit|
          post update_max_capacity_admin_spaces_path, params: { space_id: space.id, max_capacity: no_limit }
          expect(space.reload.max_capacity).to be_nil
          space.update!(max_capacity: 12)
        end
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
        expect(flash[:alert]).to start_with("The space manager was not added. ")
        SpaceManagerJoin.create!(user: manager, space: space)
        patch add_space_manager_admin_spaces_path, params: { space_id: space.id, space_manager_id: manager.id }
        expect(flash[:alert]).to start_with("The space manager was not added. ")
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
        expect(flash[:alert]).to eq("The text you typed does not match the space name, so nothing was deleted.")
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

      it "keeps the space, its pi readers and its request state, and says why, when a signed walk-in sheet refuses the delete" do
        create(:walk_in_safety_sheet, :is_adult, user: create(:user), space: space)
        reader = create(:pi_reader, space: space)
        space.update!(destroy_admin_id: admin.id)
        sign_in_as(:admin)

        expect { destroy_space("ALPHA") }.not_to change(Space, :count)

        expect(response).to redirect_to(admin_spaces_path)
        expect(flash[:alert]).to include("walk in safety sheets")
        expect(flash[:notice]).to be_nil
        expect(space.reload.destroy_admin_id).to be_nil
        expect(reader.reload.space_id).to eq(space.id)
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
        expect(flash[:alert]).to eq(I18n.t("errors.admin.spaces.calendar_space_missing", locale: :en))
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

      it "opens the failure flash in French for a French request" do
        put update_staff_needed_calendars_admin_spaces_path(locale: "fr"),
            params: { space_id: space.id, staff_needed_calendar: [url], staff_needed_calendar_role: ["bogus"] }
        expect(flash[:alert]).to start_with("Les calendriers n'ont pas été enregistrés (rien n'a changé) :")
      end

      it "saves nothing and flashes an error when a calendar has an invalid role" do
        keep = StaffNeededCalendar.create!(space: space, calendar_url: "https://old.test/x.ics")
        save_calendars(staff_needed_calendar: [url], staff_needed_calendar_role: ["bogus"])
        expect(flash[:notice]).to be_nil
        expect(flash[:alert]).to include("Calendars were not saved").and include("Role")
        expect(StaffNeededCalendar.where(space: space)).to eq([keep])
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
    end
  end
end
