require "rails_helper"

# Chunk 12: the Credly (Acclaim) boundary. Excon is intercepted by WebMock
# (spec/support/webmock.rb), so every call is stubbed at the HTTP edge.
#
# WART(D-T31): the badges / badge_templates tables were dropped (migration
# 20250613150014) but Badge, BadgeTemplate, CredlyConcern, lib/tasks/badges.rake
# remain: the HTTP layer works, everything that touches the models' tables fails.

RSpec.describe "Credly integration boundary" do
  let(:acclaim) { Rails.application.credentials[:test][:acclaim] }
  let(:token_url) { acclaim[:oauth_token_endpoint] }
  let(:root) { "#{acclaim[:url]}/v1/organizations/#{acclaim[:organisation]}/" }

  before do
    stub_request(:post, token_url).to_return(status: 200, body: { access_token: "tok123" }.to_json)
  end

  it "requests an OAuth client_credentials token with the badge scopes" do
    expect(CredlyConcern.access_token).to eq("tok123")
    expect(a_request(:post, token_url).with { |r|
      b = JSON.parse(r.body)
      b["grant_type"] == "client_credentials" && b["scope"] == "badge_templates issued_badges" &&
        b["client_id"] == acclaim[:oauth_application_id]
    }).to have_been_made.once
  end

  it "builds the endpoint root from the credentials (domain/v1/organizations/<org>/)" do
    expect(CredlyConcern.endpoint_root).to eq(root)
  end

  it "fetches badge templates with a Bearer token" do
    stub = stub_request(:get, "#{root}/badge_templates").with(headers: { "Authorization" => "Bearer tok123" })
           .to_return(status: 200, body: { data: [{ id: "t1" }] }.to_json)
    expect(BadgeTemplate.acclaim_api_get_all_badge_templates).to eq("data" => [{ "id" => "t1" }])
    expect(stub).to have_been_requested
  end

  it "fetches the accepted/rejected/pending issued badges" do
    stub = stub_request(:get, "#{root}/high_volume_issued_badge_search?filter=state::accepted,rejected,pending")
           .to_return(status: 200, body: { data: [], metadata: {} }.to_json)
    expect(Badge.acclaim_api_get_all_badges).to eq("data" => [], "metadata" => {})
    expect(stub).to have_been_requested
  end

  it "creates a badge for a user (names split on the first space, notification suppressed in test)" do
    user = create(:user, name: "Ada Lovelace Byron")
    stub = stub_request(:post, "#{root}/badges").with { |r|
      b = JSON.parse(r.body)
      b["recipient_email"] == user.email && b["badge_template_id"] == "tpl1" &&
        b["issued_to_first_name"] == "Ada" && b["issued_to_last_name"] == "Lovelace Byron" &&
        b["suppress_revoke_notification_email"] == true
    }.to_return(status: 201, body: { data: { id: "b1" } }.to_json)
    expect(Badge.acclaim_api_create_badge(user, "tpl1").status).to eq(201)
    expect(stub).to have_been_requested
  end

  it "revokes and deletes a badge through PUT /revoke and DELETE (on an unpersisted stand-in)" do
    badge = Badge.allocate # Badge.new itself raises: no table
    badge.define_singleton_method(:acclaim_badge_id) { "b9" }
    revoke = stub_request(:put, "#{root}/badges/b9/revoke").to_return(status: 200, body: "{}")
    del = stub_request(:delete, "#{root}/badges/b9").to_return(status: 204, body: "")
    expect(badge.acclaim_api_revoke_badge.status).to eq(200)
    expect(badge.acclaim_api_delete_badge.status).to eq(204)
    expect(revoke).to have_been_requested
    expect(del).to have_been_requested
  end

  it "raises ArgumentError for an unknown HTTP verb" do
    expect { Badge.credly_api_call(:patch, endpoint: "/x") }.to raise_error(ArgumentError, "Invalid HTTP verb")
  end

  it "has no tables behind the models any more" do
    expect(Badge.table_exists?).to be(false)
    expect(BadgeTemplate.table_exists?).to be(false)
    expect { Badge.count }.to raise_error(ActiveRecord::StatementInvalid, /badges/)
  end

  # WART(D-T32): Badge.create_badge calls `flash` inside a model class method (NameError) and reads proficient_project.badge_template
  it "Badge.create_badge cannot work: the template lookup fails before any HTTP call" do
    order_item = create(:order_item)
    expect { Badge.create_badge(order_item.id) }.to raise_error(StandardError)
    expect(a_request(:post, %r{/badges\z})).not_to have_been_made
  end
end
