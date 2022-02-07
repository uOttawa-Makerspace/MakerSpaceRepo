require 'stripe'
Stripe.api_key = Rails.application.credentials[Rails.env.to_sym][:stripe][:api_key]
StripeEvent.signing_secret = Rails.application.credentials[Rails.env.to_sym][:stripe][:webhook_secret_key]
StripeEvent.configure do |events|
  events.subscribe 'payout.paid' do |event|

    obj = Stripe::Payout.retrieve(
      id: event.data.object.id,
      expand: ['destination']
    ).data.object
    date = Time.at(obj.arrival_date).strftime("%Y-%m-%d")

    MsrMailer.send_email_for_stripe_transfer(obj.id, date, obj.amount, obj.destination.bank_name, obj.destination.routing_number).deliver_now
  end
end
