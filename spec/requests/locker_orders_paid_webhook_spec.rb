# frozen_string_literal: true

require "rails_helper"

# Characterization of the Shopify `orders_paid` webhook locker path
# (CustomWebhooksController#process_locker_hook -> LockerRental#auto_assign).
# Every POST is signed with the test secret (see spec/support/shopify_webhook_helpers.rb);
# unsigned/forged ones are rejected, see the HMAC examples below. No network: payloads carry the metafield inline; the Shopify
# fallback lookup (`draft_order_metafields`) is stubbed.
RSpec.describe "Shopify orders_paid webhook (locker path)", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include ApplicationHelper

  let(:tag) { LockerRental.draft_order_operating_tag }

  def payload(rental_id, tags: [tag])
    {
      tags: tags,
      metafields: [
        { namespace: "makerepo", key: "locker_db_reference", value: rental_id.to_s }
      ]
    }
  end

  before do
    ActionMailer::Base.deliveries.clear
    allow_any_instance_of(CustomWebhooksController)
      .to receive(:draft_order_metafields).and_return(nil)
  end

  it "activates an await_payment rental: defaulted owned_until, paid_at, assigned mail delivered" do
    rental = create(:locker_rental, :await_payment)
    rental.update_column(:owned_until, nil)
    ActionMailer::Base.deliveries.clear

    freeze = Time.utc(2026, 10, 20, 12)
    travel_to(freeze) do
      perform_enqueued_jobs { signed_orders_paid(payload(rental.id)) }
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to be_blank
    rental.reload
    expect(rental.state).to eq("active")
    expect(rental.owned_until.utc.iso8601(6)).to eq("2026-12-31T23:59:59.999999Z")
    expect(rental.paid_at).to eq(freeze)
    # WART(D-L03): the webhook activation does not set decided_by
    expect(rental.decided_by).to be_present # factory's, untouched

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    mail = ActionMailer::Base.deliveries.first
    expect(mail.to).to eq([rental.rented_by.email])
    expect(mail.subject).to eq("Locker #{rental.locker.specifier} has been assigned for you")
  end

  it "keeps a pre-set owned_until" do
    rental = create(:locker_rental, :await_payment, owned_until: 20.days.from_now)
    owned = rental.owned_until
    signed_orders_paid(payload(rental.id))
    expect(rental.reload.owned_until).to be_within(1.second).of(owned)
    expect(rental.state).to eq("active")
  end

  it "is replay-safe for the state/mail: a second delivery only re-stamps paid_at and sends nothing" do
    rental = create(:locker_rental, :await_payment)
    perform_enqueued_jobs { signed_orders_paid(payload(rental.id)) }
    expect(ActionMailer::Base.deliveries.size).to eq(1)

    ActionMailer::Base.deliveries.clear
    first_paid = rental.reload.paid_at
    travel_to(1.hour.from_now) do
      perform_enqueued_jobs { signed_orders_paid(payload(rental.id)) }
    end
    expect(response).to have_http_status(:ok)
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(rental.reload.state).to eq("active")
    expect(rental.paid_at).to be > first_paid
  end

  it "ignores other tags (production tag in test env): nothing changes, no mail" do
    rental = create(:locker_rental, :await_payment)
    perform_enqueued_jobs do
      signed_orders_paid(payload(rental.id, tags: ["makerepo_locker"]))
    end
    expect(response).to have_http_status(:ok)
    expect(rental.reload.state).to eq("await_payment")
    expect(rental.paid_at).to be_nil
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "answers 200 and does nothing for an unknown rental id or missing metafield" do
    perform_enqueued_jobs do
      signed_orders_paid(payload(999_999_999))
      expect(response).to have_http_status(:ok)
      signed_orders_paid({ tags: [tag] })
      expect(response).to have_http_status(:ok)
    end
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "falls back to the Shopify draft-order metafields (stubbed) when the payload has none" do
    rental = create(:locker_rental, :await_payment)
    allow_any_instance_of(CustomWebhooksController)
      .to receive(:draft_order_metafields)
      .and_return([{ "key" => "locker_db_reference", "value" => rental.id.to_s }])

    perform_enqueued_jobs do
      signed_orders_paid({ tags: [tag], admin_graphql_api_id: "gid://shopify/Order/1" })
    end
    expect(rental.reload.state).to eq("active")
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "answers 422 when the rental cannot be activated, e.g. a reviewing rental with no locker" do
    rental = create(:locker_rental, :reviewing)
    signed_orders_paid(payload(rental.id))
    # WART(D-L04): auto_assign uses update!, so validation
    # failure surfaces as a 422 (RecordInvalid rescued by the app) rather than a 200.
    expect(response).to have_http_status(:unprocessable_content)
    expect(rental.reload.state).to eq("reviewing")
  end
  # Real Shopify payloads carry a numeric draft_order_id and no inline metafields;
  # the controller queries Shopify for them. Only the HTTP endpoint is stubbed:
  # draft_order_metafields and the GraphQL client run for real.
  describe "draft order metafield lookup over HTTP (draft_order_metafields not stubbed)" do
    let!(:rental) { create(:locker_rental, :await_payment) }
    let!(:bystander) { create(:locker_rental, :await_payment) }

    before do
      allow_any_instance_of(CustomWebhooksController).to receive(:draft_order_metafields).and_call_original
      prime_shopify_context!
    end

    def metafields_response(*fields)
      { "node" => { "metafields" => { "edges" => fields.map { |f| { "node" => f } } } } }
    end

    it "queries DraftOrder/<draft_order_id> and activates the rental referenced by the locker_db_reference metafield" do
      seen = stub_shopify_graphql("query NodeMetafields", metafields_response(
        { "namespace" => "makerepo", "key" => "locker_db_reference", "value" => rental.id.to_s }
      ))
      perform_enqueued_jobs do
        signed_orders_paid({ tags: "x, #{tag}", draft_order_id: 424_242, admin_graphql_api_id: "gid://shopify/Order/9" })
      end

      expect(response).to have_http_status(:ok)
      expect(seen.size).to eq(1)
      expect_shopify_auth(seen.first)
      expect(seen.first[:body]["query"]).to include("query NodeMetafields($ownerId: ID!)")
      expect(seen.first[:body]["variables"]).to eq("ownerId" => "gid://shopify/DraftOrder/424242")
      expect(rental.reload.state).to eq("active")
      expect(bystander.reload.state).to eq("await_payment")
      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it "uses admin_graphql_api_id when there is no draft_order_id" do
      seen = stub_shopify_graphql("query NodeMetafields", metafields_response(
        { "namespace" => "makerepo", "key" => "locker_db_reference", "value" => rental.id.to_s }
      ))
      signed_orders_paid({ tags: [tag], admin_graphql_api_id: "gid://shopify/Order/9" })
      expect(seen.map { |r| r[:body]["variables"] }).to eq([{ "ownerId" => "gid://shopify/Order/9" }])
      expect(rental.reload.state).to eq("active")
      expect(bystander.reload.state).to eq("await_payment")
    end

    it "picks the locker_db_reference field among other metafields (a decoy listed first is ignored)" do
      stub_shopify_graphql("query NodeMetafields", metafields_response(
        { "namespace" => "makerepo", "key" => "membership_db_reference", "value" => bystander.id.to_s },
        { "namespace" => "makerepo", "key" => "locker_db_reference", "value" => rental.id.to_s }
      ))
      signed_orders_paid({ tags: [tag], draft_order_id: 5 })
      expect(rental.reload.state).to eq("active")
      expect(bystander.reload.state).to eq("await_payment")
    end

    it "does nothing when Shopify returns no locker_db_reference" do
      stub_shopify_graphql("query NodeMetafields", metafields_response)
      signed_orders_paid({ tags: [tag], draft_order_id: 1 })
      expect(response).to have_http_status(:ok)
      expect(LockerRental.where(state: "active")).to be_empty
    end
  end

end
