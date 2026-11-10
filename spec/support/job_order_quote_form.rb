# The quote and decline forms always send the id of the newest status row they were rendered from, and the
# endpoints refuse a request without it. Request specs that submit a quote therefore send it like the form does,
# unless the example sets `status_row_id` itself (a blank value is how a request without the field is simulated).
module JobOrderQuoteForm
  QUOTE_PATH = %r{\A/job_orders/(\d+)/quote\z}

  def patch(path, **args)
    order_id = path.to_s[QUOTE_PATH, 1]
    params = args[:params]
    if order_id && params.is_a?(Hash) && !params.key?(:status_row_id) && !params.key?("status_row_id")
      args = args.merge(params: params.merge(status_row_id: JobOrderStatus.where(job_order_id: order_id).maximum(:id)))
    end
    super(path, **args)
  end
end

RSpec.configure { |config| config.prepend JobOrderQuoteForm, type: :request }
