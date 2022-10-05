require "rails_helper"

RSpec.describe Admin::ShiftsController, type: :controller do
  before(:all) { @admin = create(:user, :admin) }

  before(:each) do
    session[:expires_at] = DateTime.tomorrow.end_of_day
    session[:user_id] = @admin.id
  end

  describe "GET /index" do
    context "logged as regular user" do
      it "should return 200" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :index
        expect(response).to redirect_to root_path
      end
    end

    context "logged as admin" do
      it "should return 200" do
        Space.find_or_create_by(name: "Makerspace")
        get :index
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /shifts" do
    context "logged as regular user" do
      it "should return 200" do
        user = create(:user, :regular_user)
        session[:user_id] = user.id
        get :shifts
        expect(response).to redirect_to root_path
      end
    end

    context "logged as admin" do
      it "should return 200" do
        Space.find_or_create_by(name: "Makerspace")
        get :shifts
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe "GET /get_availabilities" do
    context "get availabilities" do
      it "should get all the availabilities from the staffs" do
        sa1 = create(:staff_availability)
        sa2 = create(:staff_availability)
        sa3 = create(:staff_availability)
        space1 = create(:space)
        space2 = create(:space)

        User.find(@admin.id).update(space_id: space1.id)

        ss1 = StaffSpace.create(space_id: space1.id, user_id: sa1.user_id)
        ss2 = StaffSpace.create(space_id: space1.id, user_id: sa2.user_id)
        StaffSpace.create(space_id: space2.id, user_id: sa2.user_id)
        StaffSpace.create(space_id: space2.id, user_id: sa3.user_id)

        get :get_availabilities, params: { space_id: space1.id }
        expect(response).to have_http_status(:success)
        expect(response.body).to eq(
          [
            {
              title: "#{sa1.user.name} is unavailable",
              id: sa1.id,
              daysOfWeek: [sa1.day],
              startTime: sa1.start_time.strftime("%H:%M"),
              endTime: sa1.end_time.strftime("%H:%M"),
              color:
                "rgba(#{ss1.color.match(/^#(..)(..)(..)$/).captures.map(&:hex).join(", ")}, 1)",
              userId: sa1.user.id,
              className: sa1.user.name.strip.downcase.gsub(" ", "-")
            },
            {
              title: "#{sa2.user.name} is unavailable",
              id: sa2.id,
              daysOfWeek: [sa2.day],
              startTime: sa2.start_time.strftime("%H:%M"),
              endTime: sa2.end_time.strftime("%H:%M"),
              color:
                "rgba(#{ss2.color.match(/^#(..)(..)(..)$/).captures.map(&:hex).join(", ")}, 1)",
              userId: sa2.user.id,
              className: sa2.user.name.strip.downcase.gsub(" ", "-")
            }
          ].to_json
        )

        get :get_availabilities,
            params: {
              space_id: space1.id,
              transparent: true
            }
        expect(response).to have_http_status(:success)
        expect(response.body).to eq(
          [
            {
              title: "#{sa1.user.name} is unavailable",
              id: sa1.id,
              daysOfWeek: [sa1.day],
              startTime: sa1.start_time.strftime("%H:%M"),
              endTime: sa1.end_time.strftime("%H:%M"),
              color:
                "rgba(#{ss1.color.match(/^#(..)(..)(..)$/).captures.map(&:hex).join(", ")}, 0.25)",
              userId: sa1.user.id,
              className: sa1.user.name.strip.downcase.gsub(" ", "-")
            },
            {
              title: "#{sa2.user.name} is unavailable",
              id: sa2.id,
              daysOfWeek: [sa2.day],
              startTime: sa2.start_time.strftime("%H:%M"),
              endTime: sa2.end_time.strftime("%H:%M"),
              color:
                "rgba(#{ss2.color.match(/^#(..)(..)(..)$/).captures.map(&:hex).join(", ")}, 0.25)",
              userId: sa2.user.id,
              className: sa2.user.name.strip.downcase.gsub(" ", "-")
            }
          ].to_json
        )
      end
    end
  end

  describe "GET /get_shifts" do
    context "get shifts" do
      it "should get all the shifts from the staffs" do
        space = create(:space)
        s1 = create(:shift, space_id: space.id, pending: false)
        s2 = create(:shift)
        s3 = create(:shift, space_id: space.id)

        User.find(@admin.id).update(space_id: space.id)

        s1.users << create(:user, :staff)

        StaffSpace.create(user_id: s1.users.first.id, space_id: s1.space_id)
        StaffSpace.create(user_id: s1.users.second.id, space_id: s1.space_id)
        StaffSpace.create(user_id: s2.users.first.id, space_id: s2.space_id)
        StaffSpace.create(user_id: s3.users.first.id, space_id: s3.space_id)

        get :get_shifts
        expect(response).to have_http_status(:success)
        expect(response.body).to include_json(
          [
            {
              title:
                /(#{s1.reason} for (#{s1.users.first.name}|#{s1.users.second.name}), (#{s1.users.first.name}|#{s1.users.second.name})|#{s3.reason} for #{s3.users.first.name})/,
              id: s1.id || s3.id,
              start:
                s1.start_datetime.strftime("%Y-%m-%dT%H:%M:%S.%3N%:z") ||
                  s3.start_datetime.strftime("%Y-%m-%dT%H:%M:%S.%3N%:z"),
              end:
                s1.end_datetime.strftime("%Y-%m-%dT%H:%M:%S.%3N%:z") ||
                  s3.end_datetime.strftime("%Y-%m-%dT%H:%M:%S.%3N%:z"),
              color:
                /(rgba\((#{s3.color(space.id).match(/^#(..)(..)(..)$/).captures.map(&:hex).join(", ")}|#{s1.color(space.id).match(/^#(..)(..)(..)$/).captures.map(&:hex).join(", ")}), (1|0.7))/,
              className:
                /((user-#{s1.users.first.id}|user-#{s1.users.second.id}|user-#{s3.users.first.id}))/
            },
            {
              title:
                /(#{s1.reason} for (#{s1.users.first.name}|#{s1.users.second.name}), (#{s1.users.first.name}|#{s1.users.second.name})|#{s3.reason} for #{s3.users.first.name})/,
              id: s3.id || s1.id,
              start:
                s3.start_datetime.strftime("%Y-%m-%dT%H:%M:%S.%3N%:z") ||
                  s1.start_datetime.strftime("%Y-%m-%dT%H:%M:%S.%3N%:z"),
              end:
                s3.end_datetime.strftime("%Y-%m-%dT%H:%M:%S.%3N%:z") ||
                  s1.end_datetime.strftime("%Y-%m-%dT%H:%M:%S.%3N%:z"),
              color:
                /(rgba\((#{s3.color(space.id).match(/^#(..)(..)(..)$/).captures.map(&:hex).join(", ")}|#{s1.color(space.id).match(/^#(..)(..)(..)$/).captures.map(&:hex).join(", ")}), (1|0.7))/,
              className:
                /((user-#{s1.users.first.id}|user-#{s1.users.second.id}|user-#{s3.users.first.id}))/
            }
          ]
        )
      end
    end
  end
end
