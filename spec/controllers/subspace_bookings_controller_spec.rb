require "rails_helper"
require "rspec/mocks/standalone"

RSpec.describe SubSpaceBookingController, type: :controller do
  before(:all) do
    stub_const("BookingStatus::PENDING", create(:booking_status, :pending))
    stub_const("BookingStatus::APPROVED", create(:booking_status, :approved))
    stub_const("BookingStatus::DECLINED", create(:booking_status, :rejected))
  end
  before(:each) do
    @space = create(:space)
    @subspace = create(:sub_space, space: @space)
    @user = create(:user, :regular_user)
    session[:user_id] = @user.id
    session[:expires_at] = DateTime.tomorrow.end_of_day
    @user.booking_approval = true
    @user.save
  end

  describe "GET /bookings" do
    context "get bookings" do
      it "should return a 200" do
        get :bookings, params: { room: @subspace.id }
        expect(response).to have_http_status(:success)
      end
      it "should return a 200 and list of bookings for the subspace" do
        booking = create(:sub_space_booking, sub_space: @subspace, user: @user)
        get :bookings, params: { room: @subspace.id }
        expect(JSON.parse(response.body).length).to eq(1)
      end

      it "should return a 200 and list of bookings for the subspace and only that subspace" do
        booking = create(:sub_space_booking, sub_space: @subspace, user: @user)
        @other_space = create(:space)
        @other_subspace = create(:sub_space, space: @other_space)
        @other_booking =
          create(:sub_space_booking, sub_space: @other_subspace, user: @user)
        get :bookings, params: { room: @subspace.id }
        expect(JSON.parse(response.body).length).to eq(1)
      end
    end

    describe "PUT/decline" do
      it "should return 302 and notify the user they are not permitted" do
        @user = create(:user, :regular_user)
        booking = create(:sub_space_booking, sub_space: @subspace, user: @user)
        put :decline, params: { sub_space_booking_id: booking.id }
        expect(flash[:alert]).to eq(
          "You must be an admin or staff to view this page."
        )
      end
      it "should return 302 and decline the booking" do
        @user = create(:user, :admin)
        session[:user_id] = @user.id
        booking = create(:sub_space_booking, sub_space: @subspace, user: @user)
        put :decline, params: { sub_space_booking_id: booking.id }
        expect(flash[:notice]).to eq(
          "Booking for #{booking.sub_space.name} declined successfully."
        )
        get :bookings, params: { room: @subspace.id }
        expect(JSON.parse(response.body).length).to eq(0)
      end
    end

    describe "PUT/approve" do
      it "should return 302 and notify the user they are not permitted" do
        @user = create(:user, :regular_user)
        booking = create(:sub_space_booking, sub_space: @subspace, user: @user)
        put :approve, params: { sub_space_booking_id: booking.id }
        expect(flash[:alert]).to eq(
          "You must be an admin or staff to view this page."
        )
      end
      it "should return 302 and approve the booking" do
        @user = create(:user, :admin)
        session[:user_id] = @user.id
        booking = create(:sub_space_booking, sub_space: @subspace, user: @user)
        put :approve, params: { sub_space_booking_id: booking.id }
        expect(flash[:notice]).to eq(
          "Booking for #{booking.sub_space.name} approved successfully."
        )
        get :bookings, params: { room: @subspace.id }
        expect(JSON.parse(response.body).length).to eq(1)
      end
    end

    describe "POST/create" do
      it "should return 204 and create a booking" do
        post :create,
             params: {
               sub_space_booking: {
                 sub_space_id: @subspace.id,
                 start_time: DateTime.now,
                 end_time: DateTime.now + 1.hour,
                 name: Faker::Lorem.word,
                 description: Faker::Lorem.sentence
               }
             }
        expect(flash[:notice]).to eq(
          "Booking for #{@subspace.name} created successfully."
        )
        get :bookings, params: { room: @subspace.id }
        expect(JSON.parse(response.body).length).to eq(1)
      end

      it "should return 422 and notify the user they need to enter a name" do
        post :create,
             params: {
               sub_space_booking: {
                 sub_space_id: @subspace.id,
                 start_time: DateTime.now,
                 end_time: DateTime.now + 1.hour,
                 description: Faker::Lorem.sentence
               }
             }
        expect(JSON.parse(response.body)["errors"].length).to eq(1)
      end

      it "should return 422 and notify the user they need to enter a description" do
        post :create,
             params: {
               sub_space_booking: {
                 sub_space_id: @subspace.id,
                 start_time: DateTime.now,
                 end_time: DateTime.now + 1.hour,
                 name: Faker::Lorem.word
               }
             }
        expect(JSON.parse(response.body)["errors"].length).to eq(1)
      end

      it "should return 422 and notify the user they need to enter a start time" do
        post :create,
             params: {
               sub_space_booking: {
                 sub_space_id: @subspace.id,
                 end_time: DateTime.now + 1.hour,
                 name: Faker::Lorem.word,
                 description: Faker::Lorem.sentence
               }
             }
        expect(JSON.parse(response.body)["errors"].length).to eq(1)
      end

      it "should return 422 and notify the user they need to enter a end time" do
        post :create,
             params: {
               sub_space_booking: {
                 sub_space_id: @subspace.id,
                 start_time: DateTime.now,
                 name: Faker::Lorem.word,
                 description: Faker::Lorem.sentence
               }
             }
        expect(JSON.parse(response.body)["errors"].length).to eq(1)
      end

      it "should return 422 and notify the user they have exceeded the booking limit" do
        subspace = create(:sub_space, space: @space)
        subspace.maximum_booking_duration = 4
        subspace.save
        post :create,
             params: {
               sub_space_booking: {
                 sub_space_id: subspace.id,
                 start_time: DateTime.now,
                 end_time: DateTime.now + 5.hour,
                 name: Faker::Lorem.word,
                 description: Faker::Lorem.sentence
               }
             }
        expect(JSON.parse(response.body)["errors"].length).to eq(1)
      end

      it "should return 422 and notify the user they have exceeded the weekly booking limit" do
        subspace = create(:sub_space, space: @space)
        subspace.maximum_booking_hours_per_week = 4
        subspace.save
        1..2.times do
          post :create,
               params: {
                 sub_space_booking: {
                   sub_space_id: subspace.id,
                   start_time: DateTime.now,
                   end_time: DateTime.now + 3.hour,
                   name: Faker::Lorem.word,
                   description: Faker::Lorem.sentence
                 }
               }
        end
        expect(JSON.parse(response.body)["errors"].length).to eq(1)
      end

      it "should return 302 and allow the admin to exceed the booking limits" do
        @user = create(:user, :admin)
        session[:user_id] = @user.id
        subspace = create(:sub_space, space: @space)
        subspace.maximum_booking_duration = 4
        subspace.maximum_booking_hours_per_week = 5
        subspace.save
        1..2.times do
          post :create,
               params: {
                 sub_space_booking: {
                   sub_space_id: subspace.id,
                   start_time: DateTime.now,
                   end_time: DateTime.now + 10.hour,
                   name: Faker::Lorem.word,
                   description: Faker::Lorem.sentence
                 }
               }
        end
        expect(flash[:notice]).to eq(
          "Booking for #{subspace.name} created successfully."
        )
      end
    end
  end
end
