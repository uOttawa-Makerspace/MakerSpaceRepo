require "rails_helper"

include ApplicationHelper

RSpec.describe LockerRentalsController, type: :controller do
  before(:each) do
    @current_user = create(:user, :admin)
    session[:user_id] = @current_user.id
    session[:expires_at] = DateTime.tomorrow.end_of_day
  end

  describe "GET /" do
    context "as anyone" do
      it "should return only owned rentals" do
        get :index
        expect(response).to have_http_status :success

        session[:user_id] = create(:user, :regular_user).id
        get :index
        expect(response).to have_http_status :success

        session[:user_id] = create(:user, :staff).id
        get :index
        expect(response).to have_http_status :success
      end
    end
  end

  describe "GET /:id" do
    context "as admin" do
      it "shows locker rentals" do
        locker_rental = create :locker_rental, :reviewing
        get :show, params: { id: locker_rental.id }
        expect(response).to have_http_status :success
      end
    end

    context "as non admin" do
      before(:each) do
        @current_user = create(:user)
        session[:user_id] = @current_user.id
      end
      it "shows owned locker rental" do
        locker_rental = create(:locker_rental, rented_by: @current_user)
        get :show, params: { id: locker_rental.id }
        expect(response).to have_http_status :success
      end

      it "denies showing other locker rentals" do
        locker_rental = create :locker_rental
        get :show, params: { id: locker_rental.id }
        expect(response).not_to have_http_status :success
      end
    end
  end

  describe "GET /new" do
    context "as anyone" do
      it "shows the new rental page" do
        # as admin
        get :new
        expect(response).to have_http_status :success

        # as a regular user
        session[:user_id] = create(:user).id
        get :new
        expect(response).to have_http_status :success
      end
    end
  end

  # Users can:
  # Create one request at a time
  # choose the locker type only
  # cancel a request
  # They can't change notes after editin
  # They can't update anything other than cancelling
  describe "POST /" do
    context "as admin" do
      before(:all) { @locker_type = create :locker_type }

      it "should allow manual assignment" do
        target_user = create :user
        expect {
          post :create,
               params: {
                 locker_rental: {
                   locker_type_id: @locker_type.id,
                   rented_by_id: target_user.id,
                   locker_specifier: "1",
                   state: :active,
                   owned_until: end_of_this_semester
                 }
               }
        }.to change(LockerRental, :count).by(1)
        expect(response).to redirect_to :new_locker_rental
        expect(ActionMailer)
      end

      it "should ensure specifiers are unique" do
        target_user = create :user
        post_body = {
          locker_rental: {
            locker_type_id: @locker_type.id,
            rented_by_id: target_user.id,
            locker_specifier: "1",
            state: :active,
            owned_until: end_of_this_semester
          }
        }

        # Make a rental
        expect { post :create, params: post_body }.to change(
          LockerRental,
          :count
        ).by(1)

        # Make a rental with same specifier and type
        expect { post :create, params: post_body }.to change(
          LockerRental,
          :count
        ).by(0)

        # Change rental specifier
        post_body[:locker_rental][:locker_specifier] = "2"
        expect { post :create, params: post_body }.to change(
          LockerRental,
          :count
        ).by(1)
      end

      it "should assign requests when approved requests" do
        rental = create :locker_rental
        patch :update,
              params: {
                id: rental.id,
                locker_rental: {
                  state: "active"
                }
              }
        rental.reload
        expect(flash[:alert]).to eq nil
        # state is now active
        expect(rental.state).to eq "active"
        # owned until is some time in the future
        expect(rental.owned_until.to_date).to be >= Date.today
        # locker specifier is not null
        expect(rental.locker_specifier).not_to eq nil
      end
    end
  end
end
