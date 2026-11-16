# frozen_string_literal: true

require "rails_helper"

# Page script app/javascript/entrypoints/repositories.js: the owner search on
# the new repository form asks /repositories/populate_users as the user types.
RSpec.describe "Repository owner search", type: :system, skip_bullet: true do
  let(:author) { create(:user, :regular_user) }
  let(:wrapper) { find("#owner_select + .ts-wrapper") }
  let(:search_input) { wrapper.find(".ts-control input") }

  before do
    create(:user, :regular_user, username: "zeldaqx")
    log_in_as(author, to: new_repository_path(user_username: author.username))
    expect(page).to have_css("#owner_select.tomselected", visible: :all)
    wait_for_app_js
    # record the searches the page sends, to check the query it puts in the URL
    page.execute_script(<<~JS)
      const send = window.fetch.bind(window);
      window.recordedSearches = [];
      window.fetch = (input, init) => {
        window.recordedSearches.push(String(input));
        return send(input, init);
      };
    JS
    search_input.click
  end

  def recorded_search_terms
    page.evaluate_script("window.recordedSearches").map do |url|
      Rack::Utils.parse_query(URI.parse(url).query)["search"]
    end
  end

  it "lists the users whose username contains the typed text" do
    search_input.send_keys("zeldaq")
    expect(wrapper).to have_css(".ts-dropdown .option", text: "zeldaqx")
    expect(recorded_search_terms).to eq(["zeldaq"])
  end

  it "sends the whole typed text when it holds &, # or +" do
    search_input.send_keys("zel&d#a+q")
    wait_until("no search sent") { recorded_search_terms.any? }
    expect(recorded_search_terms.last).to eq("zel&d#a+q")
    expect(wrapper).to have_no_css(".ts-dropdown .option", text: "zeldaqx")
  end
end
