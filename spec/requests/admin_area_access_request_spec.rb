require "rails_helper"

# The shared gate of every admin page (AdminAreaController): a guest is sent
# to the login page and comes back to the page afterwards, a script or JSON
# request from a guest gets a 401, a signed-in user who is not an admin goes
# to the home page, and an admin gets in.
RSpec.describe "Admin area access", type: :request do
  pages = {
    "users" => -> { admin_users_path },
    "keys" => -> { admin_keys_path },
    "calendar" => -> { admin_calendar_index_path },
    "trainings" => -> { admin_trainings_path },
    "settings" => -> { admin_settings_path },
    "lockers" => -> { lockers_path },
    "questions" => -> { questions_path }
  }

  pages.each do |name, path|
    describe name do
      it "sends a guest to the login page, back to the page afterwards" do
        get instance_exec(&path)

        expect(response).to redirect_to(login_path(back_to: instance_exec(&path)))
      end

      it "sends a regular user to the home page" do
        sign_in_as(:regular)
        get instance_exec(&path)

        expect(response).to redirect_to("/")
      end

      it "sends staff to the home page" do
        sign_in_as(:staff)
        get instance_exec(&path)

        expect(response).to redirect_to("/")
      end

      it "lets an admin in" do
        sign_in_as(:admin)
        get instance_exec(&path)

        expect(response).not_to be_redirect
      end
    end
  end

  it "answers a guest's JSON request with 401" do
    get admin_users_path, headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "does not run a guest's write" do
    key = create(:key, :regular_key_type, :inventory_status, space: create(:space))

    expect { delete admin_key_path(key) }.not_to change(Key, :count)
    expect(response).to redirect_to(login_path)
  end
end
