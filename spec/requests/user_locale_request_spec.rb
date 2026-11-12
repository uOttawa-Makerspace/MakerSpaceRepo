# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Saving the language a signed-in user picks", type: :request do
  let(:password) { "asa32A353#" }
  let(:user) { create(:user, :regular_user) }

  before { block_external_http! }

  def sign_in = post(login_authentication_path, params: { username_email: user.username, password: password })

  it "saves the language picked with ?locale=" do
    sign_in
    get root_path(locale: "fr")
    expect(user.reload.locale).to eq("fr")

    get root_path(locale: "en")
    expect(user.reload.locale).to eq("en")
  end

  it "keeps the saved language on pages opened without ?locale=" do
    sign_in
    get root_path(locale: "fr")
    get root_path
    expect(user.reload.locale).to eq("fr")
  end

  it "ignores a language the site does not offer" do
    sign_in
    get root_path(locale: "fr")
    get root_path(locale: "de")
    expect(user.reload.locale).to eq("fr")
  end

  it "saves nothing for a guest" do
    user
    expect { get root_path(locale: "fr") }.not_to(change { User.where.not(locale: nil).count })
  end
end
