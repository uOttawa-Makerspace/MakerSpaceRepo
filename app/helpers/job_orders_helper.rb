module JobOrdersHelper
  def next_step
    new_job_order_path(step: @step+1)
  end

  def previous_step
    new_job_order_path(step: @step-1)
  end
end
