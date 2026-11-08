# frozen_string_literal: true

require "rails_helper"

# The shared answers to a request that fails: the 404 for a missing record, the
# message naming a missing form field, and the error pages (ErrorsController) that
# Rails shows through config.exceptions_app for unexpected errors.
RSpec.describe "Error answers", type: :request do
  let(:json_headers) { { "Accept" => "application/json" } }

  def sign_in(user = create(:user, :regular_user))
    post login_authentication_path, params: { username_email: user.username, password: "asa32A353#" }
    user
  end

  # Runs the request the way production does: exceptions rendered by the exceptions app,
  # no debug page.
  def with_production_error_pages
    env_config = Rails.application.env_config
    previous = env_config.slice("action_dispatch.show_exceptions", "action_dispatch.show_detailed_exceptions")
    env_config["action_dispatch.show_exceptions"] = :all
    env_config["action_dispatch.show_detailed_exceptions"] = false
    yield
  ensure
    env_config.merge!(previous)
  end

  describe "a record that does not exist" do
    before { sign_in }

    it "answers the translated 404 page" do
      get repository_path("nobody", "nope-nope")
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("Page not found", "could not be found")
    end

    it "answers the page in French" do
      get repository_path("nobody", "nope-nope"), params: { locale: "fr" }
      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("Page introuvable", 'lang="fr"')
    end

    it "answers JSON with the message and the reference" do
      get repository_path("nobody", "nope-nope"), headers: json_headers
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body).to eq(
        "error" => I18n.t("errors.generic.not_found"),
        "reference" => response.headers["X-Request-Id"].first(8)
      )
    end
  end

  describe "a missing form field" do
    before { sign_in }

    it "redirects home and names the field" do
      post chat_messages_path, params: { other: "x" }
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(
        "The form is missing required information (chat_message). Reload the page and try again."
      )
    end

    it "names the field in French" do
      post chat_messages_path, params: { other: "x", locale: "fr" }
      expect(flash[:alert]).to eq(
        "Il manque des informations obligatoires dans le formulaire (chat_message). Rechargez la page et réessayez."
      )
    end

    it "answers JSON 400 with the message and the reference" do
      post chat_messages_path, params: { other: "x" }, headers: json_headers
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body.keys).to contain_exactly("error", "reference")
      expect(response.parsed_body["error"]).to include("chat_message")
    end
  end

  describe "the error pages" do
    before { allow_any_instance_of(StaticPagesController).to receive(:home).and_raise(error) }

    context "with an unexpected error" do
      let(:error) { RuntimeError.new("secret internal detail") }

      it "shows the reference, the translated text and nothing from the exception" do
        with_production_error_pages { get root_path }
        reference = response.headers["X-Request-Id"].first(8)
        expect(response).to have_http_status(:internal_server_error)
        expect(response.body).to include("Something went wrong on our side", reference)
        expect(response.body).not_to include("secret internal detail")
      end

      it "shows the page in the locale of the request" do
        with_production_error_pages { get root_path, params: { locale: "fr" } }
        expect(response.body).to include(CGI.escapeHTML("Une erreur s'est produite de notre côté"), "Référence")
      end

      it "answers JSON with the reference" do
        with_production_error_pages { get root_path, headers: json_headers }
        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body["reference"]).to eq(response.headers["X-Request-Id"].first(8))
        expect(response.parsed_body["error"]).to include(response.parsed_body["reference"])
      end

      it "does not touch the database to render" do
        queries = []
        callback = ->(*, payload) { queries << payload[:sql] unless payload[:name] == "SCHEMA" }
        with_production_error_pages do
          allow_any_instance_of(StaticPagesController).to receive(:home).and_raise(RuntimeError)
          ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { get root_path }
        end
        expect(queries).to be_empty
      end
    end

    context "with an unprocessable request" do
      let(:error) { ActiveRecord::RecordInvalid.new(User.new) }

      it "shows the 422 page with a reference" do
        with_production_error_pages { get root_path }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Request could not be processed", response.headers["X-Request-Id"].first(8))
      end
    end

    context "when a POST fails" do
      let(:error) { RuntimeError.new("boom") }

      it "still shows the page (no form token is needed to render it)" do
        allow_any_instance_of(StaticPagesController).to receive(:home).and_raise(error)
        with_production_error_pages { post "/500" }
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end

  describe "the API" do
    it "adds the reference to the error body" do
      get "/api/v1/nothing-here"
      expect(response).to have_http_status(:not_found)
      error = response.parsed_body["error"]
      expect(error).to include("code" => "not_found", "message" => "Not found")
      expect(error["reference"]).to eq(response.headers["X-Request-Id"].first(8))
    end
  end
end
