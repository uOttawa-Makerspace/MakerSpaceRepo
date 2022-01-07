StripeEvent.signing_secret = Rails.application.credentials[Rails.env.to_sym][:stripe][:webhook_secret_key]
StripeEvent.configure do |events|
  events.subscribe 'payout.paid' do |event|
    date = Time.at(event.created).strftime("%Y-%m-%d")
    obj = event.data.object
    MsrMailer.send_email_for_stripe_transfer(obj.id, date, obj.amount, obj.bank_account.bank_name, obj.bank_account.routing_number).deliver_now
  end
end
