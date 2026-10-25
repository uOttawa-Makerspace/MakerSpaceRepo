# frozen_string_literal: true

require "rails_helper"

# Characterization of the Shopify `orders_paid` webhook locker path
# (CustomWebhooksController#process_locker_hook -> LockerRental#auto_assign).
# Signature verification is not mixed in under the test env, so the POST is
# unsigned. No network: payloads carry the metafield inline; the Shopify
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
      perform_enqueued_jobs { post orders_paid_custom_webhooks_path, params: payload(rental.id), as: :json }
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
    post orders_paid_custom_webhooks_path, params: payload(rental.id), as: :json
    expect(rental.reload.owned_until).to be_within(1.second).of(owned)
    expect(rental.state).to eq("active")
  end

  it "is replay-safe for the state/mail: a second delivery only re-stamps paid_at and sends nothing" do
    rental = create(:locker_rental, :await_payment)
    perform_enqueued_jobs { post orders_paid_custom_webhooks_path, params: payload(rental.id), as: :json }
    expect(ActionMailer::Base.deliveries.size).to eq(1)

    ActionMailer::Base.deliveries.clear
    first_paid = rental.reload.paid_at
    travel_to(1.hour.from_now) do
      perform_enqueued_jobs { post orders_paid_custom_webhooks_path, params: payload(rental.id), as: :json }
    end
    expect(response).to have_http_status(:ok)
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(rental.reload.state).to eq("active")
    expect(rental.paid_at).to be > first_paid
  end

  it "ignores other tags (production tag in test env): nothing changes, no mail" do
    rental = create(:locker_rental, :await_payment)
    perform_enqueued_jobs do
      post orders_paid_custom_webhooks_path, params: payload(rental.id, tags: ["makerepo_locker"]), as: :json
    end
    expect(response).to have_http_status(:ok)
    expect(rental.reload.state).to eq("await_payment")
    expect(rental.paid_at).to be_nil
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "answers 200 and does nothing for an unknown rental id or missing metafield" do
    perform_enqueued_jobs do
      post orders_paid_custom_webhooks_path, params: payload(999_999_999), as: :json
      expect(response).to have_http_status(:ok)
      post orders_paid_custom_webhooks_path, params: { tags: [tag] }, as: :json
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
      post orders_paid_custom_webhooks_path,
           params: { tags: [tag], admin_graphql_api_id: "gid://shopify/Order/1" },
           as: :json
    end
    expect(rental.reload.state).to eq("active")
    expect(ActionMailer::Base.deliveries.size).to eq(1)
  end

  it "answers 422 when the rental cannot be activated, e.g. a reviewing rental with no locker" do
    rental = create(:locker_rental, :reviewing)
    post orders_paid_custom_webhooks_path, params: payload(rental.id), as: :json
    # WART(D-L04): auto_assign uses update!, so validation
    # failure surfaces as a 422 (RecordInvalid rescued by the app) rather than a 200.
    expect(response).to have_http_status(:unprocessable_content)
    expect(rental.reload.state).to eq("reviewing")
  end
end
