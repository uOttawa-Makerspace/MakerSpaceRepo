# Collecting payments

We used to have stripe for payment processing, but due to admin pressure we
moved to shopify instead. Stripe used to have a simple API pathway, send a POST
to an endpoint with a receipt and it returns a URL with a way to collect money.
Once done it hits an endpoint on makerepo.com. Test mode was nice, and much less
state to track.

To emulate similar behaviour, we use Shopify draft orders. They allow us to
charge arbitrary amounts and line items.

Draft orders are persisted forever. Draft orders request a payment method. After
completing checkout, the draft order is permanently closed and a plain order is
created. If paying by cash, draft order is marked as payment pending. If by
credit card, order is marked as paid and the 'orders/paid' webhook is fired.
Metafields and tags are copied over to the new order.

Shopify webhooks are installed in `config/initializers/shopify.rb` and handled
in `custom_webhooks_controller.rb`. Metafields by default are not returned in
the webhook response, we need to specify them.

Using Shopify requires us to track the draft order global ID, which is something
we need to do anyways for accounting reasons (in case of bugs, proof of payment,
etc...)
.

For interacting with Shopify use the `ShopifyConcern` concern. Right now it is
geared towards imitating Stripe behaviour and transparently generate a checkout
URL. Please keep all Shopify API calls to that one file, as the API changes
frequently and centralizing interactions with it will greatly simplify future
development/debugging.

When a checkout url for a record is requested, the following steps happen:

1. Concern checks if a `shopify_draft_order_id` field is set.

- If yes, fetch `invoiceUrl` and return.

2. If not set, create a draft order with line items prepared
3. Store the newly created draft order into the `shopify_draft_order_id` field
4. Fetch and return `invoiceUrl`

We do not check if the draft order is 'paid', users would be shown status after
following the invoice url. After using the url, wait until an `orders/paid`
webhook is sent.

Once receiving the `orders/paid` webhook, webhook handler performs:

1. Checks tag associated with order. Some are NOT production orders, but can be
   created by staging/development/test(!) records. Skip if not meant for us
2. Check for presence of metadata fields. Each model owns a metafield key with
   the record ID value.
3. Use the `db_reference` value to search in DB for the record, update data
4. Return HTTP 200 OK. This is important, Shopify will keep repeating if not
   received within 1 minute

The webhook would also return an `order_id` reference to a Shopify order, but
that requires more permissions to be added to the API key. We are also not
interested in the order beyond being marked as 'PAID'

- https://github.com/Shopify/shopify_app/blob/main/docs/shopify_app/webhooks.md
- https://github.com/Shopify/shopify_app/blob/main/docs/shopify_app/sessions.md#getting-sessions-from-a-shop-or-user-model-record---with_shopify_session

Only orders 60 days old are accessible. Make sure you don't keep them for as
long. Unless we're a private app?
https://shopify.dev/docs/api/admin-graphql/latest/queries/order
