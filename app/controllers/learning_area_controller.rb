class LearningAreaController < DevelopmentProgramsController
  # Package scripts are static files loaded by <script> tags, not dynamic
  # responses; the cross-origin JavaScript check would answer them 422.
  skip_after_action :verify_same_origin_request, only: :serve_scorm_asset, raise: false
  before_action :only_admin_access, only: %i[new create edit update destroy reorder retry_scorm]
  before_action :set_learning_module,
                only: %i[
                  show
                  destroy
                  edit
                  update
                  scorm_launch
                  serve_scorm_asset
                  scorm_commit
                  retry_scorm
                ]

  # A byte-range answer covers at most this much
  SCORM_RANGE_WINDOW = 5.megabytes

  before_action :form_training_data, only: %i[new edit create update]
  before_action :with_development_header

  def index
    # Get all modules, group by training and separate into subskills. Modules
    # with no subskill get put in a separate subskill page.
    @learning_modules =
      LearningModule
        .includes(photos_attachments: :blob)
        .includes(:training)
        .group_by(&:training)
        .sort_by { |training, _| training.name }
        .to_h
        .transform_values do |modules|
          modules.sort_by { |m| LearningModule.levels.keys.index(m.level) }
        end
  end

  def new
    @learning_module = LearningModule.new
  end

  def show
  end

  def subskill
    @subskill = params[:subskill]
    @learning_modules = LearningModule.where(subskill: params[:subskill])
  end

  def create
    @learning_module = LearningModule.new(learning_module_params)
    if @learning_module.save
      redirect_to learning_area_path(@learning_module.id),
                  notice: 'Learning Module has been successfully created.'
    else
      flash[:alert] = 'Something went wrong'
      render 'new', status: :unprocessable_content
    end
  end

  def destroy
    @learning_module.destroy
    respond_to do |format|
      format.html do
        redirect_to learning_area_index_path,
                    notice: 'Learning Module has been successfully deleted.'
      end
      format.json { head :no_content }
    end
  end

  def edit
  end

  def update
    if @learning_module.update(learning_module_params)
      redirect_to learning_area_path(@learning_module.id),
                  notice: 'Learning module successfully updated.'
    else
      flash[:alert] = "Unable to apply the changes."
      @training_categories = Training.all.order(:name).pluck(:name, :id)
      @training_levels ||= TrainingSession.return_levels
      @files = @learning_module.project_files_attachments.order(created_at: :asc)
      @photos = @learning_module.photos || []
      @videos = @learning_module.videos_attachments.order(created_at: :asc)
      render "edit", status: :unprocessable_content
    end
  end

  def scorm_launch
    unless @learning_module.scorm_ready?
      return(
        render json: {
                 error: 'SCORM package not ready'
               },
               status: :unprocessable_entity
      )
    end

    redirect_to scorm_asset_learning_area_url(
                  @learning_module,
                  path: @learning_module.scorm_entry_point
                ),
                allow_other_host: true
  end

  def serve_scorm_asset
    return scorm_refusal(:not_found) unless @learning_module.scorm_ready?

    # Reconstruct blob key from request path and stored prefix. Stored names
    # are NFC, so a link written in another normalization form still finds them.
    path = params[:path].to_s
    return scorm_refusal(:not_found) unless path.valid_encoding?

    path = path.unicode_normalize(:nfc)
    key = "#{@learning_module.scorm_prefix}/#{path}"
    blob = @learning_module.scorm_package_files.blobs.find_by(key: key)
    return scorm_refusal(:not_found) unless blob

    ext = File.extname(path.presence || blob.filename.to_s)
    content_type = Rack::Mime.mime_type(ext, blob.content_type || 'application/octet-stream')

    stream_scorm_blob blob, content_type
  end

  def retry_scorm
    if @learning_module.retry_scorm_extraction
      notice = 'SCORM extraction has been queued again.'
    else
      alert = 'SCORM extraction is not retryable right now.'
    end
    redirect_to edit_learning_area_path(@learning_module.id), notice:, alert:
  end

  def scorm_commit
    # Progress is only reported by the module's own package once it has been extracted
    unless @learning_module.scorm_trackable?
      return(
        render json: {
                 error: 'SCORM package not ready'
               },
               status: :unprocessable_entity
      )
    end

    LearningModuleTrack
      .for_user_and_module!(current_user, @learning_module)
      .update(scorm_state: scorm_state_params)

    head :ok
  end

  def reorder
    if params[:data].present?
      lm_order =
        LearningModule.where(id: params[:data]).order(:order).pluck(:order)
      params[:data].each_with_index do |lm, i|
        LearningModule.find(lm).update(order: lm_order[i])
      end

      respond_to do |format|
        format.html do
          redirect_to learning_area_index_path,
                      notice: 'Successfully reordered the learning modules!'
        end
        format.json { render json: { status: :ok } }
      end
    else
      flash[
        :alert
      ] = 'Unable to re-order the learning modules. Please try again later...'
    end
  end

  private

  # A minimal answer: no success headers are set before the content is known
  # to be readable, so there is nothing to clear.
  def scorm_refusal(status, headers = {})
    headers.each { |name, value| response.headers[name] = value }
    response.cache_control.replace(no_store: true)
    head status
  end

  # ActiveStorage's send_blob_stream serves html, scripts and styles as a
  # download, which package content must not be, so the type, inline
  # disposition and byte ranges (RFC 9110) are handled here. The response is a
  # plain body with an exact Content-Length, not a live stream.
  def stream_scorm_blob(blob, content_type)
    # A cached copy is confirmed before anything is read from storage
    if request.etag_matches?(scorm_etag(blob))
      set_scorm_validators(blob)
      return head :not_modified
    end

    size = blob.byte_size
    range = scorm_byte_range(request.headers['Range'], size)
    if range == :unsatisfiable
      return scorm_refusal(:range_not_satisfiable, 'Content-Range' => "bytes */#{size}")
    end

    # A whole file is read in 1 MB ranged slices too: media players ask for
    # ranges anyway, so one code path serves both.
    sent = range || (size.positive? ? 0..(size - 1) : nil)
    body = []
    # HEAD reads nothing from storage, so a missing file still answers 200 there
    if sent && !request.head?
      begin
        body = ScormAssetBody.open(blob, sent)
      rescue ActiveStorage::FileNotFoundError
        return scorm_refusal(:not_found)
      rescue StandardError => e
        Rails.error.report(e, handled: true, context: { blob_id: blob.id })
        return scorm_refusal(:internal_server_error)
      end
    end

    set_scorm_headers(blob, content_type, sent, range)
    self.response_body = body
  end

  def set_scorm_headers(blob, content_type, sent, range)
    response.headers['Content-Type'] = content_type
    response.headers['Content-Disposition'] =
      ActionDispatch::Http::ContentDisposition.format(disposition: 'inline', filename: blob.filename.sanitized)
    response.headers['Accept-Ranges'] = 'bytes'
    response.headers['Content-Length'] = (sent ? sent.size : 0).to_s
    set_scorm_validators(blob)
    if range
      response.headers['Content-Range'] = "bytes #{range.begin}-#{range.end}/#{blob.byte_size}"
      self.status = :partial_content
    end
  end

  # A validator of our own keeps Rack::ETag from reading the body to make one
  def scorm_etag(blob)
    %("#{blob.checksum}")
  end

  # The route needs a signed-in user, so shared caches must not keep it
  def set_scorm_validators(blob)
    response.headers['ETag'] = scorm_etag(blob)
    expires_in 1.year, public: false
  end

  # The single satisfiable range to send (clamped to the window), :unsatisfiable,
  # or nil when the header is absent or to be ignored (other unit, malformed,
  # reversed, several ranges, empty file) and the whole file is sent.
  def scorm_byte_range(header, size)
    match = /\Abytes=(\d*)-(\d*)\z/i.match(header.to_s.strip)
    return if match.nil? || size.zero?

    first, last = match[1], match[2]
    if first.empty?
      return if last.empty?
      return :unsatisfiable if last.to_i.zero?

      start = [size - last.to_i, 0].max
      stop = size - 1
    else
      start = first.to_i
      stop = last.empty? ? size - 1 : last.to_i
      return if stop < start
      return :unsatisfiable if start >= size

      stop = [stop, size - 1].min
    end
    start..[stop, start + SCORM_RANGE_WINDOW - 1].min
  end

  def only_admin_access
    return if current_user.admin?
    redirect_to learning_area_index_path
  end

  # Can get module by numeric ID or by a custom shortcut
  def set_learning_module
    @learning_module =
      if params[:shortcut]
        LearningModule.find_by!(shortcut_name: params[:shortcut])
      else
        LearningModule.find(params[:id])
      end
  end

  def form_training_data
    @training_categories ||= Training.all.order(:name).pluck(:name, :id)
    @training_levels ||= LearningModule.levels.values
    @subskills ||= LearningModule.unscope(:order).distinct.pluck(:subskill)
  end

  def learning_module_params
    params.require(:learning_module).permit(
      :title,
      :description,
      :shortcut_name,
      :training_id,
      :level,
      :cc,
      :subskill,
      :scorm_package,
      :scorm_enabled,
      photos: [],
      project_files: [],
      videos: []
    )
  end

  def scorm_state_params
    # Keys lifted from flattened scorm-again format
    params
      .permit(
        :'cmi.completion_status',
        :'cmi.exit',
        :'cmi.location',
        :'cmi.progress_measure',
        :'cmi.score.scaled',
        :'cmi.score.raw',
        :'cmi.score.min',
        :'cmi.score.max',
        :'cmi.session_time',
        :'cmi.success_status',
        :'cmi.suspend_data',
        :'cmi.comments_from_learner',
        learner_preference: %i[
          audio_level
          language
          delivery_speed
          audio_captioning
        ]
      )
      .tap do |whitelisted|
        # Limit suspend data to 64kb, per the standard
        if (suspend_data = whitelisted[:'cmi.suspend_data']).is_a?(String) &&
             suspend_data.length > 64_000
          raise ActionController::BadRequest,
                'suspend_data exceeds 64k character limit'
        end
      end
  end
end
