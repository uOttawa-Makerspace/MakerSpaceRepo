# frozen_string_literal: true

require 'rails_helper'

include ApplicationHelper

RSpec.describe LockerRentalsController, type: :controller do
  before(:each) do
    LockerOption.lockers_enabled = true
    CourseName.find_or_create_by(name: 'GNG1103')
  end

  before(:each) do
    @current_user = create(:user, :admin)
    session[:user_id] = @current_user.id
    session[:expires_at] = DateTime.tomorrow.end_of_day
  end

  describe 'GET /' do
    context 'as anyone' do
      it 'should return only owned rentals' do
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

  describe 'GET /:id' do
    context 'as admin' do
      it 'shows locker rentals' do
        locker_rental = create :locker_rental, :reviewing
        get :show, params: { id: locker_rental.id }
        expect(response).to have_http_status :success
      end

      it 'shows all available lockers to staff regardless of audience' do
        general_locker = create(:locker, audience: 'general')
        gng_locker = create(:locker, audience: 'gng')
        staff_locker = create(:locker, audience: 'staff')
        
        locker_rental = create :locker_rental, :reviewing
        
        get :show, params: { id: locker_rental.id }
        
        select_options = controller.instance_variable_get(:@locker_select_options) || []
        available_ids = select_options.map { |opt| opt[1] }
        expect(available_ids).to include(general_locker.id, gng_locker.id, staff_locker.id)
      end
    end

    context 'as non admin' do
      before(:each) do
        @current_user = create(:user)
        session[:user_id] = @current_user.id
      end

      it 'shows owned locker rental' do
        locker_rental = create :locker_rental, rented_by: @current_user
        get :show, params: { id: locker_rental.id }
        expect(response).to have_http_status :success
      end

      it 'denies showing other locker rentals' do
        locker_rental = create :locker_rental
        get :show, params: { id: locker_rental.id }
        expect(response).not_to have_http_status :success
      end

      it 'only shows general lockers to regular users' do
        general_locker = create(:locker, audience: 'general')
        gng_locker = create(:locker, audience: 'gng')
        staff_locker = create(:locker, audience: 'staff')
        
        locker_rental = create :locker_rental, rented_by: @current_user
        get :show, params: { id: locker_rental.id }
        
        select_options = controller.instance_variable_get(:@locker_select_options) || []
        available_ids = select_options.map { |opt| opt[1] }
        expect(available_ids).to include(general_locker.id)
        expect(available_ids).not_to include(gng_locker.id, staff_locker.id)
      end
    end
  end

  describe 'GET /new' do
    context 'as anyone' do
      it 'shows the new rental page' do
        get :new
        expect(response).to have_http_status :success

        session[:user_id] = create(:user).id
        get :new
        expect(response).to have_http_status :success
      end
    end
  end

  describe 'Submitting locker rentals as administration' do
    before(:each) { @locker = create(:locker) }

    context 'assigning to users' do
      it 'should allow manual assignment' do
        target_user = create :user
        expect do
          post :create,
               params: {
                 locker_rental:
                   attributes_for(
                     :locker_rental,
                     locker_id: @locker.id,
                     rented_by_id: target_user.id,
                     locker_specifier: '1',
                     state: :active,
                     owned_until: end_of_this_semester
                   )
               }
        end.to change(LockerRental, :count).by(1).and(
          have_enqueued_mail(LockerMailer, :locker_assigned)
        )
        expect(response).to redirect_to :new_locker_rental
      end

      it 'should allow manual assignment with indefinite end date' do
        target_user = create :user
        post :create, params: {
          locker_rental: {
            locker_id: @locker.id,
            rented_by_id: target_user.id,
            state: :active,
            indefinite: '1'
          }
        }
        
        rental = LockerRental.last
        expect(rental.state).to eq 'active'
        expect(rental.owned_until).to be_nil
      end

      it 'should ensure lockers assigned are unique' do
        target_user = create :user
        post_body = {
          locker_rental:
            attributes_for(
              :locker_rental,
              locker_id: @locker.id,
              rented_by_id: target_user.id,
              locker_specifier: '1',
              state: :active,
              owned_until: end_of_this_semester
            )
        }
        expect { post :create, params: post_body }.to change(
          LockerRental,
          :count
        ).by(1)

        expect { post :create, params: post_body }.to change(
          LockerRental,
          :count
        ).by(0)

        post_body[:locker_rental][:locker_id] = create(:locker).id
        expect { post :create, params: post_body }.to change(
          LockerRental,
          :count
        ).by(1)
      end

      it 'should free up lockers when cancelled' do
        active_request = create :locker_rental, :active
        expect do
          create(:locker_rental, :active, locker: active_request.locker)
        end.to raise_error(ActiveRecord::RecordInvalid)

        expect do
          post :create,
               params: {
                 locker_params: {
                   rented_by_id: active_request.rented_by.id,
                   locker_id: active_request.locker.id,
                   state: :active
                 }
               }
        end.to change { LockerRental.count }.by(0)

        expect do
          patch :update,
                params: {
                  id: active_request.id,
                  locker_rental: {
                    state: :cancelled
                  }
                },
                as: :json
        end.to change { active_request.reload.state }.from('active').to(
          'cancelled'
        )

        expect {
          post :create,
               params:
                 attributes_for(
                   :locker_rental,
                   rented_by_id: active_request.rented_by.id,
                   locker_id: active_request.locker.id,
                   state: :active
                 )
        }.to change { LockerRental.count }.by(1)

        expect(LockerRental.last.locker).to eq(active_request.locker)
      end

      it 'should send emails when assigned' do
        locker_rental = create :locker_rental, :reviewing
        expect do
          patch :update,
                params: {
                  id: locker_rental.id,
                  locker_rental: {
                    state: 'active',
                    locker_id: @locker.id
                  }
                }
        end.to change { locker_rental.reload.state }.from('reviewing').to(
          'active'
        ).and have_enqueued_mail LockerMailer, :locker_assigned
      end

      it 'should reject assignments with missing info' do
        target_user = create :user
        expect do
          patch :create,
                params: {
                  locker_rental: {
                    locker_specifier: '9',
                    rented_by: target_user.id,
                    state: 'active'
                  }
                }
        end.to change(LockerRental, :count).by(0)
        expect(response).to have_http_status :unprocessable_content
      end
    end

    context 'acting on requests' do
      it 'should auto fill in requests when approving' do
        rental = create :locker_rental
        patch :update,
              params: {
                id: rental.id,
                locker_rental: {
                  state: 'active',
                  locker_id: @locker.id
                }
              }
        rental.reload
        expect(flash[:alert]).to eq nil
        expect(rental.state).to eq 'active'
        expect(rental.owned_until.to_date).to be >= Date.today
        expect(rental.locker).not_to eq nil
      end

      it 'should allow moving an active rental to indefinite' do
        rental = create(:locker_rental, :active, owned_until: 1.month.from_now)
        new_locker = create(:locker)
        
        patch :update, params: {
          id: rental.id,
          locker_rental: {
            state: :active,
            locker_id: new_locker.id,
            indefinite: '1'
          }
        }
        
        rental.reload
        expect(rental.locker_id).to eq new_locker.id
        expect(rental.owned_until).to be_nil
      end

      it 'should send users to checkout' do
        rental = create :locker_rental
        expect do
          patch :update,
                params: {
                  id: rental.id,
                  locker_rental: {
                    state: :await_payment,
                    locker_id: @locker.id
                  }
                }
        end.to change { rental.reload.state }.from('reviewing').to(
          'await_payment'
        ).and have_enqueued_mail LockerMailer, :locker_checkout
      end

      it 'should renew expired active rentals' do
        owner = create(:user)
        rental = create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.ago)
        session[:user_id] = owner.id

        expect do
          patch :renew, params: { id: rental.id }
        end.to change { rental.reload.state }.from('active').to('await_payment')

        expect(rental.owned_until.to_date).to eq end_of_this_semester.to_date
        expect(response).to redirect_to(rental)
      end

      it 'does not renew active rentals that are not expired' do
        owner = create(:user)
        rental = create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.from_now)
        session[:user_id] = owner.id

        patch :renew, params: { id: rental.id }

        expect(response).to redirect_to(rental)
        expect(flash[:alert]).to eq 'This locker rental is not renewable.'
        expect(rental.reload.state).to eq('active')
      end

      it 'does not allow other users to renew a rental' do
        owner = create(:user)
        rental = create(:locker_rental, :active, rented_by: owner, owned_until: 1.week.ago)
        session[:user_id] = create(:user).id

        patch :renew, params: { id: rental.id }

        expect(response).not_to have_http_status(:success)
        expect(rental.reload.state).to eq('active')
      end

      it 'should cancel rentals' do
        rental = create :locker_rental, :active
        expect do
          patch :update,
                params: {
                  id: rental.id,
                  locker_rental: {
                    state: :cancelled
                  }
                }
        end.to change { LockerRental.count }.by(0).and change {
                rental.reload.state
              }.from('active').to(
                'cancelled'
              ).and have_enqueued_mail LockerMailer, :locker_cancelled
      end
    end

    describe 'PATCH #toggle_contacted' do
      it 'toggles contacted_for_clearance from false to true' do
        locker_rental = create(:locker_rental, :active, contacted_for_clearance: false)
        patch :toggle_contacted, params: { id: locker_rental.id }
        expect(response).to have_http_status :success
        expect(locker_rental.reload.contacted_for_clearance).to eq(true)
      end

      it 'toggles contacted_for_clearance from true to false' do
        locker_rental = create(:locker_rental, :active, contacted_for_clearance: true)
        patch :toggle_contacted, params: { id: locker_rental.id }
        expect(response).to have_http_status :success
        expect(locker_rental.reload.contacted_for_clearance).to eq(false)
      end
    end
  end

  describe 'requesting rentals as a user' do
    before do
      @current_user = create(:user, :regular_user)
      session[:user_id] = @current_user.id
    end

    context 'creating requests' do
      before(:each) { @locker = create(:locker) }

      it 'should create a request' do
        request_note = 'Testing request notes'
        expect do
          post :create,
               params: {
                 locker_rental:
                   attributes_for(:locker_rental, notes: request_note)
               }
        end.to change { LockerRental.count }.by(
          1
        ).and have_enqueued_mail LockerMailer, :locker_requested
        last_rental = LockerRental.last
        expect(last_rental.rented_by_id).to eq @current_user.id
        expect(last_rental.notes).to eq request_note
        expect(last_rental.state).to eq 'reviewing'
      end

      it 'should require GNG project information' do
        expect do
          post :create,
               params: {
                 locker_rental:
                   attributes_for(:locker_rental, :student, :with_repository)
               }
        end.to change { LockerRental.count }.by(0)

        rental_attributes =
          attributes_for(
            :locker_rental,
            :student,
            :with_repository,
            :with_section_information
          )
        expect do
          post :create, params: { locker_rental: rental_attributes }
        end.to change { LockerRental.count }.by(
          1
        ).and have_enqueued_mail LockerMailer, :locker_requested

        last_rental = LockerRental.last
        expect(last_rental.rented_by_id).to eq @current_user.id
        expect(last_rental.state).to eq 'reviewing'

        expect(last_rental.section_name).to eq rental_attributes[:section_name]
        expect(last_rental.team_name).to eq rental_attributes[:team_name]
      end

      it 'should prevent requests when rentals are disabled' do
        LockerOption.lockers_enabled = false
        expect do
          post :create,
               params: {
                 locker_rental: attributes_for(:locker_rental)
               }
        end.to change { LockerRental.count }.by(0)
        expect(flash[:alert]).not_to be_nil
        LockerOption.lockers_enabled = true
        expect do
          post :create,
               params: {
                 locker_rental: attributes_for(:locker_rental)
               }
        end.to change { LockerRental.count }.by(1)
      end

      it 'should force only requests' do
        expect do
          post :create,
               params: {
                 locker_rental:
                   attributes_for(
                     :locker_rental,
                     state: 'active',
                     locker_id: @locker.id
                   )
               }
        end.to change { LockerRental.count }.by(
          1
        ).and have_enqueued_mail LockerMailer, :locker_requested
        expect(LockerRental.last.state).to eq 'reviewing'
        expect(LockerRental.last.locker_id).to be_nil
      end

      it 'should only allow requests for self' do
        other_user = create :user, :admin
        expect do
          post :create,
               params: {
                 locker_rental:
                   attributes_for(
                     :locker_rental,
                     locker_id: @locker.id,
                     rented_by_id: other_user.id
                   )
               }
        end.to change { LockerRental.count }.by(1)
        expect(LockerRental.last.rented_by_id).to eq @current_user.id
      end

      it 'should only allow one request per user' do
        prev_rental =
          create :locker_rental, :reviewing, rented_by: @current_user
        expect {
          post :create,
               params: {
                 locker_rental:
                   attributes_for(:locker_rental, locker_id: create(:locker).id)
               }
        }.to change { LockerRental.count }.by(0)

        session[:user_id] = create(:user, :staff).id
        post :update,
             params: {
               id: prev_rental.id,
               locker_rental: {
                 state: 'active',
                 locker_id: @locker.id
               }
             }

        session[:user_id] = @current_user.id
        expect {
          post :create,
               params: {
                 locker_rental:
                   attributes_for(:locker_rental, locker_id: create(:locker).id)
               }
        }.to change { LockerRental.count }.by(1)
      end

      it 'should not allow changing state after requesting' do
        locker_rental =
          create :locker_rental, :reviewing, rented_by: @current_user
        patch :update,
              params: {
                id: locker_rental.id,
                locker_rental: {
                  state: :active
                }
              }
        expect(locker_rental.reload.state).to eq 'reviewing'
      end

      it 'should not allow changing notes after requesting' do
        locker_rental =
          create :locker_rental, :reviewing, :notes, rented_by: @current_user
        prev_notes = locker_rental.notes
        patch :update,
              params: {
                id: locker_rental.id,
                locker_rental: {
                  notes: 'changing notes!'
                }
              }
        expect(locker_rental.reload.notes).to eq prev_notes
      end

      it 'should not allow modifying requests of other users' do
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
        expect(locker_rental.reload.state).to eq('await_payment')
      end
    end

    context 'locker request cancellation' do
      before(:each) do
        @locker_rental =
          create :locker_rental, :reviewing, rented_by: @current_user
      end

      it 'should send a cancellation email to unapproved rentals' do
        expect {
          patch :update,
                params: {
                  id: @locker_rental.id,
                  locker_rental: {
                    state: :cancelled
                  }
                }
        }.to have_enqueued_mail LockerMailer, :locker_cancelled
        expect(@locker_rental.reload.state).to eq 'cancelled'
      end

      it 'should send a cancellation email to approved rentals' do
        session[:user_id] = create(:user, :staff).id
        patch :update,
              params: {
                id: @locker_rental.id,
                locker_rental: {
                  locker_id: create(:locker).id,
                  state: :active
                }
              }
        expect(@locker_rental.reload.state).to eq 'active'

        patch :update,
              params: {
                id: @locker_rental.id,
                locker_rental: {
                  state: :cancelled
                }
              }
        expect(@locker_rental.reload.state).to eq 'cancelled'
      end

      it 'should prevent cancelling requests not owned' do
        @locker_rental = create :locker_rental, :reviewing
        patch :update,
              params: {
                id: @locker_rental.id,
                locker_rental: {
                  state: :cancelled
                }
              }
        expect(@locker_rental.reload.state).to eq 'reviewing'
      end

      it 'should prevent reopening requests' do
        @locker_rental = create :locker_rental, :active
        @locker_rental.update(state: :cancelled)
        patch :update,
              params: {
                id: @locker_rental.id,
                locker_rental: {
                  state: :active
                }
              }
        expect(@locker_rental.reload.state).to eq 'cancelled'
      end

      it 'should not allow users to cancel active rentals' do
        expect(@current_user.admin?).to eq false
        @locker_rental =
          create(:locker_rental, :active, rented_by: @current_user)
        expect(@locker_rental.reload.state).to eq 'active'
        patch :update,
              params: {
                id: @locker_rental.id,
                locker_rental: {
                  state: 'cancelled'
                }
              }
        expect(@locker_rental.reload.state).to eq 'active'
      end
    end
  end
end
