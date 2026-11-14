# frozen_string_literal: true

# Downloads one stored file of a job order for someone who may see that order (its owner, staff and admins).
# The file is streamed from storage, so the page never hands out an Active Storage URL.
class JobOrders::FilesController < ApplicationController
  include ActiveStorage::Streaming

  before_action :signed_in

  def show
    job_order = JobOrder.not_deleted.find(params[:job_order_id])
    raise ActiveRecord::RecordNotFound unless job_order.accessible_by?(current_user)

    blob = job_order.file_attachments.find(params[:id]).blob
    response.headers["Content-Length"] = blob.byte_size.to_s
    send_blob_stream blob, disposition: :attachment
  end
end
