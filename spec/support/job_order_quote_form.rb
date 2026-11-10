# The quote and decline forms always send the id of the newest status row they were rendered from, and the
# endpoints refuse a request without it. `patch_quote` submits the form: by default with the order's newest status
# row id, or with the given `status_row_id` (a stale id, or a blank one for a request without the field).
module JobOrderQuoteForm
  def patch_quote(order, params = {}, status_row_id: order.job_order_statuses.reorder(id: :desc).limit(1).pick(:id))
    patch job_order_quote_path(order), params: params.merge(status_row_id: status_row_id)
  end
end

RSpec.configure { |config| config.include JobOrderQuoteForm, type: :request }
