# frozen_string_literal: true

require "rails_helper"

# Chunk 17: StaticPagesController (homepage, info pages, forms).
#
# StaticPagesController < SessionsController. Its only before_actions are
# session_expiry / current_user / no_container, so EVERY page is public: a
# guest has `current_user = User.new`, never nil.
#
# The homepage calls two external services (Simpli.events workshops, Shopify
# collections). Each has a rescue-to-fallback contract: any failure (non-2xx,
# timeout, garbage JSON, wrong shape) logs and yields [] so the page still
# renders. spec/support/webmock.rb installs happy-path empty stubs; the
# examples below re-stub them to exercise each failure mode.
RSpec.describe "Static pages", type: :request do
  let(:simpli_url) { %r{\Ahttps://simpli\.events/api/organizer/} }
  let(:shopify_url) { %r{\Ahttps://[^/]+\.myshopify\.com/admin/api/} }

  def stub_simpli(**response)
    stub_request(:get, simpli_url).to_return(**response)
  end

  def stub_shopify(**response)
    stub_request(:post, shopify_url).with(body: /collections\(first: 8\)/).to_return(**response)
  end

  def future_ms(offset_hours)
    (Time.current + offset_hours.hours).to_i * 1000
  end

  def event_json(name, start_ms)
    { "name" => name, "startTime" => start_ms }
  end

  describe "GET / (homepage) integration failure modes" do
    context "Simpli.events" do
      it "lists upcoming events from the API (sorted, max 5, past ones dropped)" do
        events = [
          event_json("Past Workshop", future_ms(-5)),
          *(1..6).map { |i| event_json("Workshop #{i}", future_ms(i)) }.reverse
        ]
        stub_simpli(status: 200, body: { events: events }.to_json)
        get root_path
        expect(response).to have_http_status(:ok)
        workshops = controller_workshops
        expect(workshops.map { |w| w["name"] }).to eq((1..5).map { |i| "Workshop #{i}" })
      end

      # WART(D-P06): workshop link/picture from the third-party API are echoed into href and style unvalidated, so a javascript: link (compromised or malicious feed) is rendered as a clickable href
      it "renders a javascript: workshop link verbatim in the href" do
        stub_simpli(status: 200, body: { events: [{ "name" => "Evil", "startTime" => future_ms(2), "link" => "javascript:alert(1)" }] }.to_json)
        get root_path
        expect(response.body).to include('href="javascript:alert(1)"')
      end

      it "renders with no workshops when the API answers 500" do
        stub_simpli(status: 500, body: "boom")
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_workshops).to eq([])
      end

      it "renders with no workshops when the API answers 404" do
        stub_simpli(status: 404, body: "")
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_workshops).to eq([])
      end

      it "renders with no workshops when the request times out" do
        stub_simpli(body: "").then.to_timeout
        stub_request(:get, simpli_url).to_timeout
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_workshops).to eq([])
      end

      it "renders with no workshops when the connection is refused" do
        stub_request(:get, simpli_url).to_raise(Errno::ECONNREFUSED)
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_workshops).to eq([])
      end

      it "renders with no workshops when the body is not JSON" do
        stub_simpli(status: 200, body: "<html>maintenance</html>")
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_workshops).to eq([])
      end

      it "renders with no workshops when the JSON has no events key" do
        stub_simpli(status: 200, body: { error: "nope" }.to_json)
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_workshops).to eq([])
      end

      it "renders with no workshops when an event lacks startTime" do
        stub_simpli(status: 200, body: { events: [{ "name" => "No time" }] }.to_json)
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_workshops).to eq([])
      end

      it "renders with no workshops when events is not an array" do
        stub_simpli(status: 200, body: { events: "garbage" }.to_json)
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_workshops).to eq([])
      end
    end

    context "Shopify collections" do
      def shopify_body(nodes)
        { data: { collections: { nodes: nodes } } }.to_json
      end

      let(:node) do
        { "id" => "gid://shopify/Collection/1", "handle" => "3d-printing", "title" => "3D Printing",
          "description" => "d", "image" => { "url" => "https://cdn.example.test/a.png" } }
      end

      it "maps collections to makerstore links" do
        stub_shopify(status: 200, body: shopify_body([node]))
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_links).to eq(
          [{ "title" => "3D Printing", "url" => "https://makerstore.ca/collections/3d-printing",
             "image" => "https://cdn.example.test/a.png" }]
        )
        expect(response.body).to include("https://makerstore.ca/collections/3d-printing")
      end

      it "keeps a link whose collection has no image (image nil)" do
        stub_shopify(status: 200, body: shopify_body([node.merge("image" => nil)]))
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_links.first["image"]).to be_nil
      end

      it "falls back to no links when Shopify answers 500" do
        stub_shopify(status: 500, body: "x")
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_links).to eq([])
      end

      it "falls back to no links when Shopify times out" do
        stub_request(:post, shopify_url).with(body: /collections\(first: 8\)/).to_timeout
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_links).to eq([])
      end

      it "falls back to no links when the body is garbage" do
        stub_shopify(status: 200, body: "not json at all")
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_links).to eq([])
      end

      it "falls back to no links when data is null" do
        stub_shopify(status: 200, body: { data: nil }.to_json)
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_links).to eq([])
      end

      it "falls back to no links when the collections key is missing" do
        stub_shopify(status: 200, body: { data: {} }.to_json)
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_links).to eq([])
      end

      it "returns no links without calling Shopify when no access token is configured" do
        allow(Rails.application.credentials).to receive(:[]).and_call_original
        allow(Rails.application.credentials).to receive(:[]).with(:test).and_return({})
        get root_path
        expect(response).to have_http_status(:ok)
        expect(controller_links).to eq([])
        expect(a_request(:post, shopify_url)).not_to have_been_made
      end
    end

    it "renders when BOTH integrations fail at once" do
      stub_simpli(status: 503, body: "")
      stub_request(:post, shopify_url).with(body: /collections\(first: 8\)/).to_timeout
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="home"')
      expect(controller_workshops).to eq([])
      expect(controller_links).to eq([])
    end
  end

  # The controller exposes assigns only through the view; read them back from
  # the rendered page's source of truth: instance variables via the request.
  def controller_workshops
    controller.instance_variable_get(:@workshops)
  end

  def controller_links
    controller.instance_variable_get(:@makerstore_links)
  end

  describe "GET / (homepage) content" do
    it "renders for a guest with the public sections and no user widgets" do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="home"')
      expect(response.body).to include("home-hours")
      expect(response.body).not_to include("home-userinfo")
      expect(controller.instance_variable_get(:@user_skills)).to eq([])
      expect(controller.instance_variable_get(:@user_tracks)).to eq([])
    end

    it "shows recent PUBLIC repositories only (private repos never listed)" do
      pub = create(:repository, title: "Public Gizmo Project")
      priv = create(:repository, :private, title: "Secret Private Project")
      get root_path
      recent = controller.instance_variable_get(:@recent_projects)
      expect(recent).to include(pub)
      expect(recent).not_to include(priv)
    end

    it "lists contact infos flagged show_hours (name order)" do
      create(:contact_info, name: "Zeta Lab", show_hours: true)
      create(:contact_info, name: "Alpha Lab", show_hours: true)
      create(:contact_info, name: "Hidden Lab", show_hours: false)
      get root_path
      expect(controller.instance_variable_get(:@contact_info).map(&:name)).to eq(["Alpha Lab", "Zeta Lab"])
    end

    it "greets a signed-in user by name" do
      user = sign_in_as(:regular)
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(user.name)
    end

    it "shows the staff resources card to staff only" do
      sign_in_as(:regular)
      get root_path
      expect(response.body).not_to include(admin_settings_path)
      expect(response.body).not_to include(staff_dashboard_index_path)
    end

    it "shows staff links to staff and the admin settings link to admins only" do
      sign_in_as(:staff)
      get root_path
      expect(response.body).to include(staff_dashboard_index_path)
      expect(response.body).not_to include(%(href="#{admin_settings_path}"))
    end

    it "shows the admin settings link to an admin" do
      sign_in_as(:admin)
      get root_path
      expect(response.body).to include(%(href="#{admin_settings_path}"))
    end

    it "lists the user's certifications and track progress for a signed-in user", :aggregate_failures do
      user = sign_in_as(:regular)
      cert = create(:certification, user: user)
      session = cert.training_session
      get root_path
      expect(controller.instance_variable_get(:@user_skills)).to eq([[session.training.name_en, session.level]])
    end

    it "locale param switches the page language and sticks in the session" do
      get root_path, params: { locale: "fr" }
      expect(response).to have_http_status(:ok)
      expect(session[:locale]).to eq(:fr)
      get root_path
      expect(session[:locale]).to eq(:fr)
    end

    it "ignores an unsupported locale param: default locale, bad value not stored" do
      get root_path, params: { locale: "xx" }
      expect(response).to have_http_status(:ok)
      expect(session[:locale]).to eq(I18n.default_locale)
    end

    it "does not 500 on an unsupported locale already in the session" do
      get root_path, params: { locale: "fr" }
      allow_any_instance_of(ActionDispatch::Request).to receive(:session).and_wrap_original do |m, *a|
        m.call(*a).tap { |sess| sess[:locale] = "xx" }
      end
      get root_path
      expect(response).to have_http_status(:ok)
    end

    it "does not leak the request locale into the calling thread" do
      get root_path, params: { locale: "fr" }
      expect(I18n.locale).to eq(I18n.default_locale)
    end
  end

  describe "home_user_widgets" do
    it "is an action with no route of its own: the path falls into the /:username catch-all" do
      expect(Rails.application.routes.recognize_path("/home_user_widgets"))
        .to include(controller: "users", action: "show", username: "home_user_widgets")
    end
  end

  describe "static info pages are public" do
    {
      "/about" => :about_path, "/contact" => :contact_path, "/terms_of_service" => :tos_path,
      "/hours" => :hours_path, "/calendar" => :calendar_path, "/get_involved" => :get_involved_path,
      "/resources" => :resources_path, "/labs" => :labs_path, "/forgot_password" => :forgot_password_path
    }.each do |path, helper|
      it "GET #{path} answers 200 for a guest and a signed-in user" do
        expect(public_send(helper)).to eq(path)
        get path
        expect(response).to have_http_status(:ok)
        sign_in_as(:regular)
        get path
        expect(response).to have_http_status(:ok)
      end
    end

    it "contact page lists ALL contact infos (including those hidden from the homepage hours)" do
      create(:contact_info, name: "Shown Lab", email: "shown@example.test", show_hours: true)
      create(:contact_info, name: "Quiet Lab", email: "quiet@example.test", show_hours: false)
      get contact_path
      expect(response.body).to include("Shown Lab", "Quiet Lab", "quiet@example.test")
    end
  end

  describe "GET /hours.json" do
    it "is an empty list while no contact info is flagged show_hours" do
      create(:contact_info, name: "Unlisted", show_hours: false)
      get hours_path(format: :json)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    # WART(D-P03): hours.json includes :opening_hour but ContactInfo only has_many :opening_hours, so the JSON endpoint 500s as soon as one contact info is listed
    it "answers 500 (NoMethodError opening_hour) once a show_hours contact info exists" do
      create(:contact_info, name: "Hours Lab", show_hours: true)
      get hours_path(format: :json)
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe "GET /open_hours (JSON from ICS feeds)" do
    it "returns [] when no open_hours calendars exist" do
      get open_hours_path
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it "returns [] (not an error) when the ICS feed fails" do
      create(:staff_needed_calendar, role: "open_hours", calendar_url: "https://calendar.example.test/feed.ics")
      stub_request(:get, "https://calendar.example.test/feed.ics").to_return(status: 500, body: "")
      get open_hours_path
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it "returns the calendar with no events when the ICS feed times out" do
      create(:staff_needed_calendar, role: "open_hours", calendar_url: "https://calendar.example.test/feed.ics")
      stub_request(:get, "https://calendar.example.test/feed.ics").to_timeout
      get open_hours_path
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.size).to eq(1)
      expect(json.first["events"]).to eq([])
    end
  end

  describe "POST /join_team_program" do
    it "asks a guest to sign in and creates nothing" do
      expect { post join_team_program_path }.not_to change(Program, :count)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("You need to sign in to join the Teams Program.")
    end

    it "joins a signed-in user to the Teams program" do
      user = sign_in_as(:regular)
      expect { post join_team_program_path }.to change { user.programs.where(program_type: Program::TEAMS).count }.by(1)
      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to start_with("You have successfully joined the Teams Program!")
    end

    it "is idempotent for a user already in the program" do
      user = sign_in_as(:regular)
      post join_team_program_path
      expect { post join_team_program_path }.not_to change(Program, :count)
      expect(flash[:alert]).to eq("You are already part of the Teams Program.")
      expect(user.programs.where(program_type: Program::TEAMS).count).to eq(1)
    end
  end

  describe "POST /reset_password (forgot password form)" do
    it "emails a reset link to an existing account (delivered outcome)" do
      user = create(:user, :regular_user)
      deliveries.clear
      patch reset_password_path, params: { email: " #{user.email.upcase} " }
      expect(response).to have_http_status(:ok)
      expect(flash[:notice]).to eq("A reset link email has been sent to the email if the account exists.")
      expect(deliveries.size).to eq(1)
      expect(deliveries.last.to).to eq([user.email])
    end

    it "gives the same answer and sends nothing for an unknown email (no account enumeration)" do
      deliveries.clear
      patch reset_password_path, params: { email: "nobody@example.test" }
      expect(response).to have_http_status(:ok)
      expect(flash[:notice]).to eq("A reset link email has been sent to the email if the account exists.")
      expect(deliveries).to be_empty
    end

    it "rejects a blank email without sending anything" do
      deliveries.clear
      patch reset_password_path, params: { email: "" }
      expect(response).to have_http_status(:ok)
      expect(flash[:alert]).to eq("Please enter an email address.")
      expect(deliveries).to be_empty
    end

    it "is reachable by a signed-in user too" do
      sign_in_as(:regular)
      patch reset_password_path, params: { email: "nobody@example.test" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /report_repository/:repository_id" do
    let(:repo) { create(:repository) }

    it "asks a guest to log in and sends nothing" do
      deliveries.clear
      post report_repository_path(repo)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Please login if you wish to report this repository")
      expect(deliveries).to be_empty
    end

    it "emails the report to the support inbox for a signed-in user (via POST)" do
      user = sign_in_as(:regular)
      deliveries.clear
      post report_repository_path(repo), headers: { "HTTP_REFERER" => "http://www.example.com/back" }
      expect(response).to redirect_to("http://www.example.com/back")
      expect(flash[:alert]).to eq("Repository has been reported")
      expect(deliveries.size).to eq(1)
      expect(deliveries.last.to).to eq(["uottawa.makerepo@gmail.com"])
      expect(deliveries.last.subject).to eq("Repository #{repo.title} reported")
      expect(deliveries.last.from).to eq([user.email])
    end

    it "redirects to root when there is no referer" do
      sign_in_as(:regular)
      post report_repository_path(repo)
      expect(response).to redirect_to(root_path)
    end

    # FIXED(D-P02): reporting is a POST; a plain GET (link, image tag, prefetch) no longer emails the support inbox
    it "does not send the email, on a plain GET" do
      sign_in_as(:regular)
      deliveries.clear
      get "/report_repository/#{repo.id}"
      expect(flash[:alert]).not_to eq("Repository has been reported")
      expect(deliveries).to be_empty
    end

    it "renders the report as a confirm-guarded POST button on the repository page" do
      sign_in_as(:regular)
      get repository_path(repo.user_username, repo)
      expect(response.body).to match(%r{<form[^>]*data-turbo-confirm=[^>]*action="/report_repository/#{repo.id}"|<form[^>]*action="/report_repository/#{repo.id}"[^>]*data-turbo-confirm=})
    end

    it "raises RecordNotFound for an unknown repository (signed in)" do
      sign_in_as(:regular)
      post report_repository_path(repository_id: 0)
      expect(response).to have_http_status(:not_found)
    end
  end
end
