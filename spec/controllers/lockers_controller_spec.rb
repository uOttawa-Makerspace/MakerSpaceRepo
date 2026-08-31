require "rails_helper"

RSpec.describe LockersController, type: :controller do
  before do
    # Stub the external API calls so they don't hit the network in tests
    allow(LockerOption).to receive(:locker_product_link).and_return("gid://shopify/Product/123")
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
  end

  before(:each) do
    @admin = create(:user, :admin)
    session[:user_id] = @admin.id
    session[:expires_at] = DateTime.tomorrow.end_of_day
  end

  describe "GET /index" do
    context "as regular user" do
      it "should deny access" do
        session[:user_id] = create(:user).id
        get :index
        expect(response).to_not have_http_status :success
      end
    end
    
    context "as staff" do
      it "should prevent access" do
        session[:user_id] = create(:user, :staff).id
        get :index
        expect(response).to_not have_http_status :success
      end
    end

    context "as admin" do
      it "should return success" do
        get :index
        expect(response).to have_http_status :success
      end
    end
  end

  describe "POST #create" do
    context "as admin" do
      it "creates a locker with notes and audience" do
        locker_size = create(:locker_size)
        expect {
          post :create, params: {
            locker: {
              specifier: '999',
              locker_size_id: locker_size.id,
              audience: 'staff',
              notes: 'Staff only locker note'
            }
          }
        }.to change(Locker, :count).by(1)
        
        locker = Locker.last
        expect(locker.specifier).to eq('999')
        expect(locker.audience).to eq('staff')
        expect(locker.notes).to eq('Staff only locker note')
        expect(response).to redirect_to(locker)
      end
    end
  end

  describe "PATCH #update" do
    context "as admin" do
      it "updates locker notes and audience" do
        locker = create(:locker, audience: 'general', notes: nil)
        patch :update, params: {
          id: locker.id,
          locker: {
            audience: 'gng',
            notes: 'GNG project locker'
          }
        }
        
        locker.reload
        expect(locker.audience).to eq('gng')
        expect(locker.notes).to eq('GNG project locker')
        expect(response).to redirect_to(locker)
      end
    end
  end

  describe "POST #create_multiple" do
    context "as admin" do
      it "creates a range of lockers" do
        locker_size = create(:locker_size)
        expect {
          post :create_multiple, params: {
            range_start: 100,
            range_end: 102,
            locker_size_id: locker_size.id
          }
        }.to change(Locker, :count).by(3)
        
        expect(Locker.pluck(:specifier)).to include('100', '101', '102')
        expect(response).to redirect_to(lockers_path(anchor: 'lockerInventory'))
      end

      it "prevents creating if range end is smaller than start" do
        locker_size = create(:locker_size)
        post :create_multiple, params: {
          range_start: 105,
          range_end: 100,
          locker_size_id: locker_size.id
        }
        
        expect(flash[:alert]).to eq('Range end must be larger than range start')
        expect(response).to redirect_to(lockers_path(anchor: 'lockerInventory'))
      end
    end
  end

  describe "PATCH #bulk_edit" do
    context "as admin" do
      it "updates selected lockers" do
        size1 = create(:locker_size)
        size2 = create(:locker_size)
        lockers = create_list(:locker, 2, locker_size: size1)
        
        patch :bulk_edit, params: {
          id: lockers.map(&:id),
          locker: { locker_size_id: size2.id }
        }
        
        lockers.each do |l|
          expect(l.reload.locker_size_id).to eq(size2.id)
        end
        expect(flash[:notice]).to eq('Lockers updated')
        expect(response).to redirect_to(lockers_path(anchor: 'lockerInventory'))
      end

      it "deletes selected lockers when bulk_delete is passed" do
        lockers = create_list(:locker, 2)
        expect {
          patch :bulk_edit, params: {
            id: lockers.map(&:id),
            bulk_delete: true
          }
        }.to change(Locker, :count).by(-2)
        
        expect(flash[:notice]).to eq('Selected lockers deleted')
      end
    end
  end

  describe "PUT #price" do
    context "as admin" do
      it "updates the Shopify product link" do
        # We stubbed the getter at the top, now stub the setter to test it's called
        expect(LockerOption).to receive(:locker_product_link=).with("gid://shopify/Product/9999")
        put :price, params: { value: '9999' }
        expect(response).to redirect_to(lockers_path)
      end
    end
  end

  describe "PUT #enabled" do
    context "as admin" do
      it "enables locker requests" do
        expect(LockerOption).to receive(:lockers_enabled=).with(true)
        put :enabled, params: { value: 't' }
        expect(response).to redirect_to(lockers_path)
      end

      it "disables locker requests" do
        expect(LockerOption).to receive(:lockers_enabled=).with(false)
        put :enabled, params: { value: 'f' }
        expect(response).to redirect_to(lockers_path)
      end
    end
  end
end