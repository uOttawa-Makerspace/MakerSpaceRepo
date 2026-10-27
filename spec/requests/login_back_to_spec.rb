# frozen_string_literal: true

require "rails_helper"

# FIXED(D-I05 follow-up / N3): a guest bounced to login only gets a back_to for
# requests that can be replayed as a GET. POST/PATCH/DELETE targets (POST-only
# actions) would 404 after login, so they fall back to a same-host referer.
RSpec.describe "Login back_to for guests", type: :request do
  let(:user) { create(:user, :regular_user) }

  def back_to_of(response)
    Rack::Utils.parse_query(URI.parse(response.location).query.to_s)["back_to"]
  end

  it "keeps back_to for a GET to a protected page (unchanged)" do
    get carts_path
    expect(response).to redirect_to(login_path(back_to: "/carts"))
  end

  it "stores no back_to for a POST to a protected action" do
    post order_items_path, params: { order_item: { quantity: 1 } }
    expect(response).to redirect_to(login_path)
    expect(back_to_of(response)).to be_nil
  end

  it "uses a same-host referer for a POST (path and query only)" do
    post order_items_path, headers: { "HTTP_REFERER" => "http://www.example.com/proficient_projects?page=2" }
    expect(back_to_of(response)).to eq("/proficient_projects?page=2")
  end

  it "ignores a foreign or malformed referer" do
    post order_items_path, headers: { "HTTP_REFERER" => "https://evil.example.org/phish" }
    expect(back_to_of(response)).to be_nil
    post order_items_path, headers: { "HTTP_REFERER" => "http://www.example.com.evil.org/x" }
    expect(back_to_of(response)).to be_nil
    post order_items_path, headers: { "HTTP_REFERER" => "ht!tp://%%%" }
    expect(back_to_of(response)).to be_nil
  end

  it "applies the same rule in staff areas" do
    post staff_dashboard_sign_out_all_users_path
    expect(back_to_of(response)).to be_nil
    post staff_dashboard_sign_out_all_users_path, headers: { "HTTP_REFERER" => "http://www.example.com/staff_dashboard" }
    expect(back_to_of(response)).to eq("/staff_dashboard")
  end

  it "gives no back_to (and no 500) for a same-host referer that is not HTTP(S)" do
    ["ftp://www.example.com/x", "//www.example.com/x"].each do |referer|
      post order_items_path, headers: { "HTTP_REFERER" => referer }
      expect(response).to redirect_to(login_path)
      expect(back_to_of(response)).to be_nil
    end
  end

  it "never stores the login page itself as the back_to" do
    post order_items_path, headers: { "HTTP_REFERER" => "http://www.example.com/login?back_to=%2Fcarts" }
    expect(response).to redirect_to(login_path)
    expect(back_to_of(response)).to be_nil
  end

  it "does the same in staff areas" do
    post staff_dashboard_sign_out_all_users_path, headers: { "HTTP_REFERER" => "ftp://www.example.com/x" }
    expect(response).to redirect_to(login_path)
  end

  it "does not put a non-GET page URL in the login modal back_to" do
    post login_authentication_path, params: { username_email: "nobody", password: "wrong" }
    modal = Nokogiri::HTML(response.body).at_css("#loginModal input[name=back_to]")
    expect(modal["value"].to_s).not_to include("login_authentication")
  end

  context "when logging in with a back_to" do
    def login_with(back_to)
      post login_authentication_path, params: { username_email: user.username, password: "asa32A353#", back_to: back_to }
    end

    it "follows a same-site path" do
      login_with("/carts")
      expect(response).to redirect_to("/carts")
    end

    ["https://evil.com", "//evil.com", "/\\evil.com", "///evil.com"].each do |bad|
      it "lands on root for #{bad}" do
        login_with(bad)
        expect(response).to redirect_to(root_path)
      end
    end
  end

  it "lands on the referring page after logging in, not on a 404" do
    post order_items_path, headers: { "HTTP_REFERER" => "http://www.example.com/carts" }
    target = back_to_of(response)
    follow_redirect!
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#", back_to: target }
    expect(response).to redirect_to("/carts")
  end
end
