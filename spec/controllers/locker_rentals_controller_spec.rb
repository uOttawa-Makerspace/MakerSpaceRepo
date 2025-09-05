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
  describe "Submitting locker rentals as administration" do
    before(:each) { @locker = create(:locker) }

    context "assigning to users" do
      it "should allow manual assignment" do
        target_user = create :user
        expect {
          post :create,
               params: {
                 locker_rental:
                   attributes_for(
                     :locker_rental,
                     locker_id: @locker.id,
                     rented_by_id: target_user.id,
                     locker_specifier: "1",
                     state: :active,
                     owned_until: end_of_this_semester
                   )
               }
        }.to change(LockerRental, :count).by(1).and change {
                ActionMailer::Base.deliveries.count
              }.by(1)
        expect(response).to redirect_to :new_locker_rental
        expect(ActionMailer::Base.deliveries.last.to).to eq [target_user.email]
        #expect(ActionMailer)
      end

      it "should ensure lockers assigned are unique" do
        target_user = create :user
        post_body = {
          locker_rental:
            attributes_for(
              :locker_rental,
              locker_id: @locker.id,
              rented_by_id: target_user.id,
              locker_specifier: "1",
              state: :active,
              owned_until: end_of_this_semester
            )
        }
        # Make a rental
        expect { post :create, params: post_body }.to change(
          LockerRental,
          :count
        ).by(1)

        # Make a rental with same locker
        expect { post :create, params: post_body }.to change(
          LockerRental,
          :count
        ).by(0)

        # Change rental locker instead
        post_body[:locker_rental][:locker_id] = create(:locker).id
        expect { post :create, params: post_body }.to change(
          LockerRental,
          :count
        ).by(1)
      end

      it "should free up lockers when cancelled" do
        # make a request in DB
        active_request = create :locker_rental, :active
        # Test model in controller tests, because this whole test suite is a parody
        expect {
          create(
            :locker_rental,
            :active,
            locker: active_request.locker,
          )
        }.to raise_error(ActiveRecord::RecordInvalid)

        # Assign a reserved specifier
        expect {
          post :create,
               params: {
                 locker_params: {
                   rented_by_id: active_request.rented_by.id,
                   locker_id: active_request.locker.id,
                   state: :active
                 }
               }
        }.to change { LockerRental.count }.by(0)

        # Cancel active rental
        expect {
          patch :update,
                params: {
                  id: active_request.id,
                  locker_rental: {
                    state: :cancelled
                  }
                },
                as: :json
        }.to change { active_request.reload.state }.from("active").to(
          "cancelled"
        )

        # Re-assign locker
        expect {
          post :create,
               params:
                 attributes_for(
                   :locker_rental,
                   rented_by_id: active_request.rented_by.id,
                   locker_id: active_request.locker.id,
                   # owned until is auto filled by controller
                   state: :active
                 )
        }.to change { LockerRental.count }.by(1)

        # specifier should be reused
        expect(LockerRental.last.locker).to eq(
          active_request.locker
        )
      end

      it "should send emails when assigned" do
        locker_rental = create :locker_rental, :reviewing
        expect {
          patch :update,
                params: {
                  id: locker_rental.id,
                  locker_rental: {
                    state: "active",
                    locker_id: @locker.id
                  }
                }
        }.to change { locker_rental.reload.state }.from("reviewing").to(
          "active"
        ).and change { ActionMailer::Base.deliveries.count }.by(1)
        last_email = ActionMailer::Base.deliveries.last
        expect(last_email.to).to eq [locker_rental.rented_by.email]
      end

      it "should reject assignments with missing info" do
        target_user = create :user
        expect {
          patch :create,
                params: {
                  locker_rental: {
                    # no locker type
                    locker_specifier: "9",
                    rented_by: target_user.id,
                    state: "active"
                    # no owned_until
                  }
                }
        }.to change(LockerRental, :count).by(0)
        expect(response).to have_http_status :unprocessable_entity
      end
    end

    context "acting on requests" do
      it "should auto fill in requests when approving" do
        rental = create :locker_rental
        patch :update,
              params: {
                id: rental.id,
                locker_rental: {
                  state: "active",
                  locker_id: @locker.id
                }
              }
        rental.reload
        expect(flash[:alert]).to eq nil
        # state is now active
        expect(rental.state).to eq "active"
        # owned until is some time in the future
        expect(rental.owned_until.to_date).to be >= Date.today
        # locker is not null
        expect(rental.locker).not_to eq nil
      end

      it "should send users to checkout" do
        rental = create :locker_rental
        expect {
          patch :update,
                params: {
                  id: rental.id,
                  locker_rental: {
                    state: :await_payment,
                    locker_id: @locker.id
                  }
                }
        }.to change { rental.reload.state }.from("reviewing").to(
          "await_payment"
        ).and change { ActionMailer::Base.deliveries.count }.by(1)
        last_mail = ActionMailer::Base.deliveries.last
        expect(last_mail.to).to eq [rental.rented_by.email]
        expect(last_mail.subject).to include("checkout")
      end

      it "should cancel rentals" do
        rental = create :locker_rental, :active
        expect {
          patch :update,
                params: {
                  id: rental.id,
                  locker_rental: {
                    state: :cancelled
                  }
                }
        }.to change { LockerRental.count }.by(0).and change {
                rental.reload.state
              }.from("active").to("cancelled").and change {
                      ActionMailer::Base.deliveries.count
                    }.by(1)
        last_mail = ActionMailer::Base.deliveries.last
        expect(last_mail.to).to eq [rental.rented_by.email]
        expect(last_mail.subject).to include("cancelled")
      end
    end
  end

  describe "requesting rentals as a user" do
    before do
      @current_user = create(:user, :regular_user)
      session[:user_id] = @current_user.id
    end

    context "creating requests" do
      before(:all) { @locker = create(:locker) }

      it "should create a request" do
        request_note = "Testing request notes"
        expect {
          post :create,
               params: {
                 locker_rental:
                   attributes_for(
                     :locker_rental,
                     notes: request_note
                   )
               }
        }.to change { LockerRental.count }.by(1)
        #.and change {ActionMailer::Base.deliveries.count}.by(1)
        last_rental = LockerRental.last
        expect(last_rental.rented_by_id).to eq @current_user.id
        expect(last_rental.notes).to eq request_note
        expect(last_rental.state).to eq "reviewing"
      end

      it "should force only requests" do
        expect {
          post :create,
               params: {
                 locker_rental:
                   attributes_for(
                     :locker_rental,
                     state: "active",
                     locker_id: @locker.id
                   )
               }
        }.to change { LockerRental.count }.by(1)
        expect(LockerRental.last.state).to eq "reviewing"
        expect(LockerRental.last.locker_id).to be_nil
      end

      it "should only allow requests for self" do
        other_user = create :user, :admin
        expect {
          post :create,
               params: {
                 locker_rental:
                   attributes_for(
                     :locker_rental,
                     locker_id: @locker.id,
                     rented_by_id: other_user.id
                   )
               }
        }.to change { LockerRental.count }.by(1)
        expect(LockerRental.last.rented_by_id).to eq @current_user.id
      end

      it "should only allow one request per user" do
        # Give current user a rental
        prev_rental =
          create :locker_rental, :reviewing, rented_by: @current_user
        # Ask for another one
        expect {
          post :create,
               params: {
                 locker_rental:
                   attributes_for(
                     :locker_rental,
                     locker_id: create(:locker).id
                   )
               }
        }.to change { LockerRental.count }.by(0)
        # Approve last request. Log in as staff
        session[:user_id] = create(:user, :staff).id
        post :update, params: {
               id: prev_rental.id,
               locker_rental: {
                 state: 'active',
                 locker_id: @locker.id,
               }
             }

        # Ask for another one. Log back in as user
        session[:user_id] = @current_user.id
        expect {
          post :create,
               params: {
                 locker_rental:
                   attributes_for(
                     :locker_rental,
                     locker_id: create(:locker).id
                   )
               }
        }.to change { LockerRental.count }.by(1)
      end

      it "should not allow changing state after requesting" do
        locker_rental =
          create :locker_rental, :reviewing, rented_by: @current_user
        patch :update,
              params: {
                id: locker_rental.id,
                locker_rental: {
                  state: :active
                }
              }
        expect(locker_rental.reload.state).to eq "reviewing"
      end

      it "should not allow changing notes after requesting" do
        locker_rental =
          create :locker_rental, :reviewing, :notes, rented_by: @current_user
        prev_notes = locker_rental.notes
        patch :update,
              params: {
                id: locker_rental.id,
                locker_rental: {
                  notes: "changing notes!"
                }
              }
        expect(locker_rental.reload.notes).to eq prev_notes
      end

      it "should not allow modifying requests of other users" do
        locker_rental =
          create(:locker_rental, :await_payment, rented_by: @current_user)
        session[:user_id] = create(:user).id
        patch :update,
              params: {
                id: locker_rental.id,
                locker_rental: {
                  state: :cancelled
                }
              }
        # stays the same
        expect(locker_rental.reload.state).to eq("await_payment")
      end
    end

    # Rather hard to test stripe in here really

    # context "locker request checkout" do
    #   it "should send emails reminding of checkout" do
    #     locker_rental = create(:locker_rental, :reviewing)
    #     patch :update, params: {
    #             id: locker_rental.id
    #           }
    #   end

    #   it "should auto assign after checkout" do
    #   end

    #   it "should not auto assign after failed checkout" do
    #   end
    # end

    context "locker request cancellation" do
      before(:each) do
        @locker_rental =
          create :locker_rental, :reviewing, rented_by: @current_user
      end

      it "should send a cancellation email to unapproved rentals" do
        patch :update,
              params: {
                id: @locker_rental.id,
                locker_rental: {
                  state: :cancelled
                }
              }
        expect(@locker_rental.reload.state).to eq "cancelled"
        last_mail = ActionMailer::Base.deliveries.last
        expect(last_mail.to).to eq [@current_user.email]
        expect(last_mail.subject).to include("cancel")
      end

      it "should send a cancellation email to approved rentals" do
        # approve a rental first
        session[:user_id] = create(:user, :staff).id
        patch :update, params: {
                id: @locker_rental.id,
                locker_rental: {
                  locker_id: create(:locker).id,
                  state: :active
                }
              }
        expect(@locker_rental.reload.state).to eq "active"
        # Then cancel it later
        patch :update,
              params: {
                id: @locker_rental.id,
                locker_rental: {
                  state: :cancelled
                }
              }
        expect(@locker_rental.reload.state).to eq "cancelled"
        last_mail = ActionMailer::Base.deliveries.last
        expect(last_mail.to).to eq [@locker_rental.rented_by.email]
        expect(last_mail.subject).to include("cancel")
      end

      it "should prevent cancelling requests not owned" do
        @locker_rental = create :locker_rental, :reviewing
        patch :update,
              params: {
                id: @locker_rental.id,
                locker_rental: {
                  state: :cancelled
                }
              }
        expect(@locker_rental.reload.state).to eq "reviewing"
        last_mail = ActionMailer::Base.deliveries.last
        expect(last_mail).to eq nil
      end

      it "should prevent reopening requests" do
        @locker_rental = create :locker_rental, :active
        @locker_rental.update(state: :cancelled)
        patch :update,
              params: {
                id: @locker_rental.id,
                locker_rental: {
                  state: :active
                }
              }
        expect(@locker_rental.reload.state).to eq "cancelled"
      end

      it "should not allow users to cancel active rentals" do
        # make sure we're not admin
        expect(@current_user.admin?).to eq false
        @locker_rental = create(:locker_rental, :active, rented_by: @current_user)
        expect(@locker_rental.reload.state).to eq "active"
        patch :update,
              params: {
                id: @locker_rental.id,
                locker_rental: {
                  state: "cancelled"
                }
              }
        expect(@locker_rental.reload.state).to eq "active"
      end
    end

    context "state keeps going one way" do
      it "can't move from active to await_payment" do
      end

      it "can't move from active to reviewing" do
      end

      it "can't move from await_payment to reviewing" do
      end

      it "can't move from cancelled to reviewing"
    end
  end
end
