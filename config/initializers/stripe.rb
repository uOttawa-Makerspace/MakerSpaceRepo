StripeEvent.signing_secret = Rails.application.credentials[Rails.env.to_sym][:stripe][:webhook_secret_key]
StripeEvent.configure do |events|
  events.subscribe 'invoice.paid' do |event|
    date = Time.at(event.created).strftime("%Y-%m-%d")
    MsrMailer.send_email_for_stripe_transfer(event.id, date, event.data.object.amount).deliver_now
  end
end
