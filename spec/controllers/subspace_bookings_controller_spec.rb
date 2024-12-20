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
  end

  describe "PUT/decline" do
    context "decline booking" do
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
  end

  describe "PUT/approve" do
    context "approve booking" do
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
  end

  describe "PUT/bulk_approve_decline" do
    context "create some bookings" do
      it "should create some bookings" do
        post :create,
             params: {
               sub_space_booking: {
                 sub_space_id: @subspace.id,
                 start_time: DateTime.now + 1.hour,
                 end_time: DateTime.now + 2.hour,
                 name: Faker::Lorem.word,
                 description: Faker::Lorem.sentence,
                 recurring: true,
                 blocking: false,
                 recurring_end: DateTime.now + 2.weeks, # 1 now + 2 later
                 recurring_frequency: "weekly"
               }
             },
             as: :json # json so booleans dont get quoted
        expect(SubSpaceBooking.all.count).to eq(3)
        expect(response).to have_http_status(:success)
        get :bookings, params: { room: @subspace.id }
        expect(JSON.parse(response.body).length).to eq(3)

        booking_ids = SubSpaceBooking.pluck(:id)
        # approve first two
        first_two_ids = booking_ids.first(2)
        put :bulk_approve_decline,
            params: {
              bulk_status: "approve",
              sub_space_booking_ids: first_two_ids
            }
        first_two_ids.each do |b_id|
          expect(
            SubSpaceBooking
              .find(b_id)
              .sub_space_booking_status
              .booking_status_id
          ).to eq(BookingStatus::APPROVED.id)

          #decline the last one
          last_id = booking_ids.last
          put :bulk_approve_decline,
              params: {
                bulk_status: "decline",
                sub_space_booking_ids: [last_id]
              }
          expect(
            SubSpaceBooking
              .find(last_id)
              .sub_space_booking_status
              .booking_status_id
          ).to eq(BookingStatus::DECLINED.id)
        end
      end
    end
  end

  describe "POST/create" do
    context "create booking" do
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

    describe "DELETE/delete" do
      it "should return 302 and delete the booking" do
        @user = create(:user, :admin)
        @booking_user = create(:user)
        session[:user_id] = @user.id
        @booking =
          create(:sub_space_booking, sub_space: @subspace, user: @booking_user)
        delete :delete, params: { sub_space_booking_id: @booking.id }
        expect(flash[:notice]).to eq(
          "Booking for #{@booking.sub_space.name} deleted successfully."
        )
      end
      it "should return 302 and delete the booking" do
        @booking_user = create(:user)
        session[:user_id] = @booking_user.id
        @booking =
          create(:sub_space_booking, sub_space: @subspace, user: @booking_user)
        delete :delete, params: { sub_space_booking_id: @booking.id }
        expect(flash[:notice]).to eq(
          "Booking for #{@booking.sub_space.name} deleted successfully."
        )
      end
      it "should return 302 and not delete the booking" do
        @user = create(:user)
        @booking_user = create(:user)
        session[:user_id] = @user.id
        @booking =
          create(:sub_space_booking, sub_space: @subspace, user: @booking_user)
        delete :delete, params: { sub_space_booking_id: @booking.id }
        expect(flash[:alert]).to eq(
          "You must be the owner of this booking or an admin to delete it."
        )
      end
    end
  end

  describe "DELETE/delete" do
    context "delete booking" do
      it "should return 302 and delete the booking" do
        @user = create(:user, :admin)
        @booking_user = create(:user)
        session[:user_id] = @user.id
        @booking =
          create(:sub_space_booking, sub_space: @subspace, user: @booking_user)
        delete :delete, params: { sub_space_booking_id: @booking.id }
        expect(flash[:notice]).to eq(
          "Booking for #{@booking.sub_space.name} deleted successfully."
        )
      end
      it "should return 302 and delete the booking" do
        @booking_user = create(:user)
        session[:user_id] = @booking_user.id
        @booking =
          create(:sub_space_booking, sub_space: @subspace, user: @booking_user)
        delete :delete, params: { sub_space_booking_id: @booking.id }
        expect(flash[:notice]).to eq(
          "Booking for #{@booking.sub_space.name} deleted successfully."
        )
      end
      it "should return 302 and not delete the booking" do
        @user = create(:user)
        @booking_user = create(:user)
        session[:user_id] = @user.id
        @booking =
          create(:sub_space_booking, sub_space: @subspace, user: @booking_user)
        delete :delete, params: { sub_space_booking_id: @booking.id }
        expect(flash[:alert]).to eq(
          "You must be the owner of this booking or an admin to delete it."
        )
      end
    end
  end
end
