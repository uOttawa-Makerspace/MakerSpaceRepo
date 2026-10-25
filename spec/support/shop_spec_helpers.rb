# frozen_string_literal: true

# Shared helpers for the Shop characterization specs (chunk 8).
#
# * `block_external_http!` is a safety net: Shopify credentials ship in the test
#   config, so the network is reachable from specs. Request specs go through
#   Rack::Test, so nothing legitimate opens a socket; any attempt raises.
# * `shop_log_in!` drives the real login POST (see job_orders_request_spec).
module ShopSpecHelpers
  class NetworkBlocked < StandardError; end

  def block_external_http!
    allow_any_instance_of(Net::HTTP).to receive(:connect) do |http|
      raise NetworkBlocked, "external HTTP attempted: #{http.address}:#{http.port}"
    end
  end

  # Records every GraphQL call the ShopifyConcern makes and answers with canned
  # draft-order payloads, so no socket is ever opened.
  class FakeShopifyAdmin
    Response = Struct.new(:code, :body)
    attr_reader :calls
    attr_accessor :invoice_url, :draft_id, :fully_paid, :user_errors, :metafields, :status

    def initialize
      @calls = []
      @invoice_url = "https://shop.example.test/invoices/abc"
      @draft_id = "gid://shopify/DraftOrder/9001"
      @fully_paid = false
      @user_errors = []
      @metafields = []
      @status = 200
    end

    def query(query:, variables: nil)
      @calls << { query: query, variables: variables }
      return Response.new(@status, nil) unless @status == 200

      if query.include?("NodeMetafields")
        Response.new(200, { "data" => { "node" => { "metafields" => { "edges" => @metafields.map { |m| { "node" => m } } } } } })
      elsif query.include?("draftOrderCreate")
        Response.new(200, { "data" => { "draftOrderCreate" => {
          "draftOrder" => (@user_errors.empty? ? { "id" => @draft_id } : nil), "userErrors" => @user_errors
        } } })
      elsif query.include?("draftOrderDelete")
        Response.new(200, { "data" => { "draftOrderDelete" => { "deletedId" => @draft_id, "userErrors" => [] } } })
      else
        Response.new(200, { "data" => { "draftOrder" => {
          "id" => @draft_id, "invoiceUrl" => @invoice_url,
          "order" => { "id" => "gid://shopify/Order/1", "fullyPaid" => @fully_paid }
        } } })
      end
    end
  end

  def stub_shopify_admin!
    fake = FakeShopifyAdmin.new
    allow(ShopifyAPI::Clients::Graphql::Admin).to receive(:new).and_return(fake)
    fake
  end

  def shop_log_in!(user, password: "asa32A353#")
    post login_authentication_path,
         params: { username_email: user.username, password: password }
    expect(response).to redirect_to(root_path)
    user
  end

  def deliveries
    ActionMailer::Base.deliveries
  end

  # Gives the user a wallet balance through a plain positive CcMoney row.
  def credit_cc!(user, amount)
    CcMoney.create!(user: user, cc: amount)
    user.update_wallet
  end

  def order_status!(name)
    OrderStatus.find_by!(name: name)
  end

  # An in-progress order owned by `user` holding one item per cc value.
  def cart_for(user, *ccs, quantity: 1)
    order = Order.create!(user: user)
    ccs.each do |cc|
      pp = create(:proficient_project, cc: cc)
      order.order_items.create!(proficient_project: pp, quantity: quantity)
    end
    order.reload
  end
end

RSpec.configure do |config|
  config.include ShopSpecHelpers, type: :request
  config.include ShopSpecHelpers, type: :model
  config.include ShopSpecHelpers, type: :system
end
