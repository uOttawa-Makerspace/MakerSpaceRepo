# frozen_string_literal: true

require "rails_helper"

# Characterization of LockersController and LockerSizesController over real
# HTTP (chunk 7). The Shopify product lookup is stubbed (no network).
RSpec.describe "Lockers and locker sizes admin", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:staff) { create(:user, :staff) }
  let(:regular) { create(:user, :regular_user) }

  def log_in!(user)
    post login_authentication_path,
         params: { username_email: user.username, password: "asa32A353#" }
    expect(response).to redirect_to(root_path)
  end

  before do
    allow(LockerOption).to receive(:locker_product_info).and_return({ variants: {} })
    LockerOption.where(name: [LockerOption::LOCKER_PRODUCT_LINK, LockerOption::LOCKERS_ENABLED]).delete_all
  end

  describe "access matrix" do
    it "sends guests to / (ensure_admin runs before signed_in; no login redirect)" do
      # WART(D-L06): unlike LockerRentals, guests are not
      # sent to the login page here.
      get lockers_path
      expect(response).to redirect_to("/")
    end

    it "redirects non-admins (regular and staff) to / on lockers#index, with no flash" do
      [regular, staff].each do |user|
        log_in!(user)
        get lockers_path
        expect(response).to redirect_to("/")
      end
    end

    it "redirects non-admins away from locker_sizes mutations and does not apply them" do
      size = create(:locker_size)
      log_in!(staff)
      expect { post locker_sizes_path, params: { locker_size: { size: "X", shopify_gid: "g" } } }
        .not_to change(LockerSize, :count)
      expect(response).to redirect_to("/")
      expect { delete locker_size_path(size) }.not_to change(LockerSize, :count)
      expect(response).to redirect_to("/")
    end
  end

  describe "LockersController as admin" do
    before { log_in!(admin) }

    it "GET index renders the inventory" do
      create(:locker, specifier: "A-100")
      get lockers_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("A-100")
    end

    it "GET show renders a locker" do
      locker = create(:locker, specifier: "B-200")
      get locker_path(locker)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("B-200")
    end

    it "GET show 404s for an unknown id" do
      get locker_path(id: 999_999_999)
      expect(response).to have_http_status(:not_found)
    end

    it "POST create makes a locker, flashes and redirects to it" do
      size = create(:locker_size)
      expect do
        post lockers_path, params: { locker: { specifier: "C-1", locker_size_id: size.id, audience: "gng" } }
      end.to change(Locker, :count).by(1)
      locker = Locker.find_by(specifier: "C-1")
      expect(response).to redirect_to(locker_path(locker))
      expect(flash[:notice]).to eq("Created locker #C-1")
      expect(locker.audience).to eq("gng")
    end

    it "POST create with a duplicate specifier re-renders index with 422 and an alert" do
      existing = create(:locker, specifier: "C-2")
      expect do
        post lockers_path, params: { locker: { specifier: "C-2", locker_size_id: existing.locker_size_id } }
      end.not_to change(Locker, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash[:alert]).to eq("Specifier has already been taken")
    end

    it "PATCH update changes notes (HTML redirect, JSON 204) and 422s when invalid" do
      locker = create(:locker, specifier: "D-1")
      patch locker_path(locker), params: { locker: { notes: "dented" } }
      expect(response).to redirect_to(locker_path(locker))
      expect(flash[:notice]).to eq("Locker updated successfully")
      expect(locker.reload.notes).to eq("dented")

      patch locker_path(locker, format: :json), params: { locker: { notes: "dented 2" } }
      expect(response).to have_http_status(:no_content)

      other = create(:locker, specifier: "D-2")
      patch locker_path(locker), params: { locker: { specifier: other.specifier } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(locker.reload.specifier).to eq("D-1")
    end

    it "DELETE destroy removes the locker and its rentals" do
      rental = create(:locker_rental, :active)
      locker = rental.locker
      expect { delete locker_path(locker) }.to change(Locker, :count).by(-1)
      expect(response).to redirect_to(lockers_path)
      expect(flash[:notice]).to eq("Locker removed")
      expect(LockerRental.exists?(rental.id)).to be false
    end

    it "POST create_multiple builds the range and rejects end <= start" do
      size = create(:locker_size)
      expect do
        post create_multiple_lockers_path,
             params: { range_start: "300", range_end: "302", locker_size_id: size.id }
      end.to change(Locker, :count).by(3)
      expect(response).to redirect_to(lockers_path(anchor: "lockerInventory"))
      expect(flash[:notice]).to eq("Lockers created")

      expect do
        post create_multiple_lockers_path,
             params: { range_start: "310", range_end: "310", locker_size_id: size.id }
      end.not_to change(Locker, :count)
      expect(flash[:alert]).to eq("Range end must be larger than range start")
    end

    it "PATCH bulk_edit updates or deletes the selected ids" do
      a = create(:locker)
      b = create(:locker)
      patch bulk_edit_lockers_path, params: { id: [a.id, b.id], locker: { notes: "bulk" } }
      expect(response).to redirect_to(lockers_path(anchor: "lockerInventory"))
      expect(flash[:notice]).to eq("Lockers updated")
      expect([a, b].map { |l| l.reload.notes }).to eq(%w[bulk bulk])

      expect do
        patch bulk_edit_lockers_path,
              params: { id: [a.id], bulk_delete: "1", locker: { notes: "x" } }
      end.to change(Locker, :count).by(-1)
      expect(flash[:notice]).to eq("Selected lockers deleted")
    end

    it "PUT price stores the product gid; PUT enabled toggles the sitewide switch" do
      put price_lockers_path, params: { value: "12345" }
      expect(response).to redirect_to(lockers_path)
      expect(LockerOption.find_by(name: "locker_product_link").value).to eq("gid://shopify/Product/12345")

      put enabled_lockers_path, params: { value: "t" }
      expect(LockerOption.lockers_enabled).to be true
      put enabled_lockers_path, params: { value: "nope" }
      expect(response).to redirect_to(lockers_path)
      expect(LockerOption.lockers_enabled).to be false
    end
  end

  describe "LockerSizesController as admin" do
    before { log_in!(admin) }

    it "POST create adds a size and redirects to the productVariants anchor" do
      expect do
        post locker_sizes_path, params: { locker_size: { size: "Large", shopify_gid: "gid://v/1" } }
      end.to change(LockerSize, :count).by(1)
      expect(response).to redirect_to(lockers_path(anchor: "productVariants"))
    end

    it "POST create with invalid data silently creates nothing and still redirects" do
      # WART(D-L07): result of LockerSize.create/update is ignored (silent failure)
      expect do
        post locker_sizes_path, params: { locker_size: { size: "", shopify_gid: "" } }
      end.not_to change(LockerSize, :count)
      expect(response).to redirect_to(lockers_path(anchor: "productVariants"))
      expect(flash[:alert]).to be_nil
    end

    it "PATCH update changes a size; DELETE destroys it" do
      size = create(:locker_size)
      patch locker_size_path(size), params: { locker_size: { size: "Huge" } }
      expect(response).to redirect_to(lockers_path)
      expect(size.reload.size).to eq("Huge")

      patch locker_size_path(size), params: { locker_size: { size: "" } }
      expect(response).to redirect_to(lockers_path)
      expect(size.reload.size).to eq("Huge")

      expect { delete locker_size_path(size) }.to change(LockerSize, :count).by(-1)
      expect(response).to redirect_to(lockers_path)
    end

    it "has a show route but no show action: 500 (missing template)" do
      # WART(D-L08): route exists without a show action/template
      get locker_size_path(create(:locker_size))
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "models" do
    it "Locker.available excludes lockers with an active rental and filters by audience" do
      free = create(:locker, audience: "gng")
      taken = create(:locker_rental, :active).locker
      reserved = create(:locker_rental, :await_payment).locker
      expect(Locker.available).to include(free, reserved)
      expect(Locker.available).not_to include(taken)
      expect(Locker.available("gng")).to include(free)
      expect(Locker.available("staff")).not_to include(free)
      expect(Locker.assigned).to contain_exactly(taken)
    end

    it "validates Locker and LockerSize" do
      locker = create(:locker, specifier: "Z-1")
      expect(build(:locker, specifier: "Z-1")).not_to be_valid
      expect(build(:locker, locker_size: nil)).not_to be_valid
      expect(Locker.public_shown).to include(locker)
      expect(build(:locker_size, size: nil)).not_to be_valid
      expect(build(:locker_size, shopify_gid: nil)).not_to be_valid
    end

    it "validates LockerOption names and the product gid format" do
      expect(LockerOption.new(name: "  Foo ").tap(&:valid?).name).to eq("foo")
      expect(LockerOption.new(name: "locker_product_link", value: "bad")).not_to be_valid
      expect(LockerOption.new(name: "locker_product_link", value: "gid://shopify/Product/9")).to be_valid
      LockerOption.lockers_enabled = true
      expect(LockerOption.new(name: "lockers_enabled")).not_to be_valid # taken
    end
  end
end
