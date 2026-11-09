# frozen_string_literal: true

class ProjectProposalsController < SessionsController
  include TurnstileHelper

  before_action :set_project_proposal, only: %i[show edit update destroy]
  before_action :current_user
  before_action :signed_in, only: %i[edit update approve decline create_revision join_project_proposal unjoin_project_proposal]
  before_action :require_admin, only: %i[approve decline]
  before_action :require_owner_or_admin, only: %i[edit update]
  before_action :require_visible_proposal, only: :show
  before_action :redirect_to_canonical_url, only: %i[show edit]
  helper_method :owner_or_admin?

  # Guests may propose a project (behind the captcha), so creation is limited per visitor
  rate_limit to: 10, within: 1.hour, only: :create,
             by: -> { current_user.id.presence || request.remote_ip },
             with: -> {
               redirect_to project_proposals_path, alert: 'Too many requests, please try again later.'
             }

  # GET /project_proposals
  def index
    scope =
      ProjectProposal
        .includes(:user, :admin, :categories, :linked_project_proposal)
        .order(created_at: :desc)
        .search(params[:query])

    scope = visible_to_viewer(scope)

    # Status filtering (handles approved: 1, 0, and nil for pending/revisions)
    if params[:status].present?
      statuses = Array(params[:status])
      include_pending = statuses.include?('nil')
      numeric_statuses = statuses.reject { |s| s == 'nil' }.map(&:to_i)

      if include_pending && numeric_statuses.any?
        scope = scope.where(approved: numeric_statuses).or(scope.where(approved: nil))
      elsif include_pending
        scope = scope.where(approved: nil)
      elsif numeric_statuses.any?
        scope = scope.where(approved: numeric_statuses)
      end
    end

    season, year = params[:semester]&.split('_')
    if ProjectProposal.seasons.keys.include?(season) && year.to_i.positive?
      scope = scope.where(season: season, year: year.to_i)
    end

    @pagy, @project_proposals = pagy(scope, limit: 20)

    respond_to do |format|
      format.js
      format.html
    end
  end

  def user_projects
    joined_scope =
      ProjectProposal
        .all
        .joins(:project_joins)
        .where(project_joins: { user: current_user })
        .order(created_at: :desc)

    pending_scope =
      current_user
        .project_proposals
        .where(approved: nil)
        .order(created_at: :desc)

    approved_scope =
      current_user
        .project_proposals
        .order(created_at: :desc)
        .where(approved: 1)

    @pagy_joined, @project_proposals_joined = pagy(with_display_users(joined_scope), page_key: 'page_joined', limit: 15)
    @pagy_pending, @user_pending_project_proposals = pagy(with_display_users(pending_scope), page_key: 'page_pending', limit: 15)
    @pagy_approved, @approved_project_proposals = pagy(with_display_users(approved_scope), page_key: 'page_approved', limit: 15)
  end

  # GET /project_proposals/1
  def show
    @categories = @project_proposal.categories
    @pagy, @repositories =
      pagy(viewable_linked_repositories.includes(:owner, :photos).order([sort_order].to_h), limit: 9)

    @project_files = @project_proposal.project_files
    @linked_pp = @project_proposal.linked_project_proposal
    @revisions =
      visible_to_viewer(
        ProjectProposal.where(linked_project_proposal_id: @project_proposal.id)
      )
  end

  # GET /project_proposals/new
  def new
    @project_proposal = ProjectProposal.new
  end

  # GET /project_proposals/1/edit
  def edit
    @categories = @project_proposal.categories
    @category_options = CategoryOption.show_options
    @photos = @project_proposal.photos
    @files = @project_proposal.project_files
  end

  def projects_assigned
    scope =
      ProjectProposal
        .joins(:project_joins)
        .joins(
          'LEFT OUTER JOIN repositories ON (project_proposals.id = repositories.project_proposal_id)'
        )
        .where('repositories.id IS NULL')
        .where(approved: 1)
        .distinct
        .order(created_at: :desc)

    @pagy, @assigned_project_proposals = pagy(with_display_users(scope), limit: 15)
  end

  def projects_completed
    scope =
      ProjectProposal
        .where(approved: 1)
        .joins(:repositories)
        .distinct
        .order(created_at: :desc)

    @pagy, @completed_project_proposals = pagy(with_display_users(scope), limit: 15)
  end

  # POST /project_proposals
  def create
    attributes = project_proposal_params.except(:categories)
    @project_proposal = ProjectProposal.new(user_id: current_user&.id)

    respond_to do |format|
      if !signed_in? && !verify_turnstile
        refuse_create(attributes)
        flash.now[:alert] = 'Captcha error, please try again'
        format.html { render :new, status: :unprocessable_content }
      elsif apply_edit(attributes)
        format.html do
          redirect_to project_proposal_path(@project_proposal),
                      notice: 'Project proposal was successfully created.'
        end
        format.json do
          render json: {
                   redirect_uri:
                     project_proposal_path(@project_proposal).to_s
                 }
        end
        MsrMailer.send_new_project_proposals.deliver_later
      else
        refuse_create(attributes)
        flash.now[:alert] = refused_alert('errors.proposals.not_created')
        format.html { render :new, status: :unprocessable_content }
        format.json do
          render json: @project_proposal.errors, status: :unprocessable_content
        end
      end
    end
  end

  def create_revision
    if params[:old_project_proposal_id] &&
         ProjectProposal.where(id: params[:old_project_proposal_id]).present?
      @old_project_proposal = ProjectProposal.find(params[:old_project_proposal_id])
      unless owner_or_admin?(@old_project_proposal)
        redirect_to project_proposals_path,
                    alert: 'You are not allowed to create a revision of this project proposal.'
        return
      end
      values = @old_project_proposal.attributes.except(
        'id',
        'user_id',
        'admin_id',
        'approved',
        'slug',
        'season',
        'year'
      )
      values['title'] = "Revision of #{@old_project_proposal.title}"
      values['linked_project_proposal_id'] = params[:old_project_proposal_id]

      @project_proposal = ProjectProposal.new(values)
      @project_proposal.user_id = current_user&.id
      unless @project_proposal.save
        return redirect_to project_proposal_path(@old_project_proposal),
                           alert: validation_message(@project_proposal, 'errors.proposals.revision_not_created')
      end

      if @old_project_proposal.photos.attached?
        @old_project_proposal.photos.each do |photo|
          @project_proposal.photos.attach(photo.blob)
        end
      end

      if @old_project_proposal.project_files.attached?
        @old_project_proposal.project_files.each do |file|
          @project_proposal.project_files.attach(file.blob)
        end
      end

      @old_project_proposal.categories.each do |category|
        Category.create(
          name: category.name,
          project_proposal_id: @project_proposal.id
        )
      end

      respond_to do |format|
        format.html do
          redirect_to project_proposal_path(@project_proposal),
                      notice:
                        'The project proposal revision has been successfully created.'
        end
        format.json do
          render json: {
                   redirect_uri:
                     project_proposal_path(@project_proposal).to_s
                 }
        end
      end
    else
      redirect_back(fallback_location: root_path, alert: I18n.t('errors.proposals.revision_source_missing'))
    end
  end

  # PATCH/PUT /project_proposals/1
  def update
    attributes = project_proposal_params.except(:categories)
    needs_re_review = @project_proposal.approved? && !current_user.admin?
    attributes = attributes.merge(approved: nil, admin_id: nil) if needs_re_review
    respond_to do |format|
      if apply_edit(attributes)
        format.html do
          redirect_to project_proposal_path(@project_proposal),
                      notice:
                        if needs_re_review
                          'Project proposal was updated. It is pending again and needs to be re-approved by an admin before it is listed publicly.'
                        else
                          'Project proposal was successfully updated.'
                        end
        end
        format.json do
          render json: {
                   redirect_uri:
                   project_proposal_path(@project_proposal).to_s
                 }
        end
      else
        refuse_edit(attributes)
        flash.now[:alert] = refused_alert('errors.proposals.not_updated')
        format.html { render :edit, status: :unprocessable_content }
        format.json do
          render json: @project_proposal.errors, status: :unprocessable_content
        end
      end
    end
  end

  # DELETE /project_proposals/1
  def destroy
    return unless current_user.admin?
    @project_proposal.destroy
    respond_to do |format|
      format.html do
        redirect_to project_proposals_url,
                    notice: 'Project proposal was successfully deleted.'
      end
      format.json { head :no_content }
    end
  end

  def approve
    @project_proposal = ProjectProposal.find(params[:id])
    @project_proposal.update(approved: 1, admin_id: current_user.id)
    redirect_to project_proposals_url, notice: 'Project Proposal Approved'
  end

  def decline
    @project_proposal = ProjectProposal.find(params[:id])
    @project_proposal.update(approved: 0, admin_id: current_user.id)
    redirect_to project_proposals_url, notice: 'Project Proposal Declined'
  end

  def join_project_proposal
    @project_proposal = ProjectProposal.find(params[:project_proposal_id])
    unless @project_proposal.approved?
      redirect_to project_proposals_path,
                  alert: 'You can only join an approved project proposal.'
      return
    end
    @project_join = ProjectJoin.new(project_join_params)
    @project_join.user_id = current_user.id
    # the only validation on a join is that a user joins a project once
    if @project_join.save
      flash[:notice] = 'You joined this project.'
    else
      flash[:alert] = I18n.t('errors.proposals.already_joined')
    end
    redirect_to project_proposal_path(@project_proposal)
  end

  def unjoin_project_proposal
    @project_proposal = ProjectProposal.find(params[:project_proposal_id])
    @project_join = @project_proposal.project_joins.find(params[:project_join_id])
    unless current_user.admin? || @project_join.user_id == current_user.id
      redirect_to project_proposal_path(@project_proposal),
                  alert: 'You can only leave a project you joined yourself.'
      return
    end
    @project_join.delete
    redirect_to project_proposal_path(@project_proposal),
                notice: 'You unjoined this project.'
  end

  private

  # Admins see everything; everyone else sees approved proposals plus their own.
  # The listing shows the proposer and reviewer to admins only, deleted accounts included.
  def with_display_users(scope)
    current_user.admin? ? scope.includes(:display_user, :display_admin) : scope
  end

  def visible_to_viewer(scope)
    return scope if current_user.admin?

    visible = ProjectProposal.where(approved: :approved)
    visible = visible.or(ProjectProposal.where(user_id: current_user.id)) if signed_in?
    scope.merge(visible)
  end

  def owner_or_admin?(proposal)
    current_user.admin? ||
      (proposal.user_id.present? && proposal.user_id == current_user.id)
  end

  def require_admin
    return if current_user.admin?

    redirect_to project_proposals_path,
                alert: 'Only admins can review project proposals.'
  end

  def require_owner_or_admin
    return if owner_or_admin?(@project_proposal)

    respond_to do |format|
      format.html do
        redirect_to project_proposals_path,
                    alert: 'You are not allowed to modify this project proposal.'
      end
      format.json { head :forbidden }
    end
  end

  def uploads_param(key)
    params[key] || params.dig(:project_proposal, key)
  end

  # Attachments the user asked to remove, by filename or attachment id. Collected before
  # anything new is attached, so a new upload sharing a name is never removed.
  def attachments_marked_for_removal(attachments, names)
    names = Array.wrap(names).map(&:to_s)
    return [] if names.empty?

    attachments.select { |a| names.include?(a.filename.to_s) || names.include?(a.id.to_s) }
  end

  def marked_attachments
    attachments_marked_for_removal(@project_proposal.photos.attachments, uploads_param(:deleteimages)) +
      attachments_marked_for_removal(@project_proposal.project_files.attachments, uploads_param(:deletefiles))
  end

  # New photos are checked before anything is saved or removed: those in the legacy images field and those in the
  # form's photos field, uploads and signed ids alike. An unreadable one refuses the create or edit.
  def new_photos_readable?
    photos = new_images + Array(project_proposal_params[:photos]).compact_blank
    return true if photos.all? { |img| readable_image?(img) }

    @project_proposal.errors.add(:photos, 'could not be read as images')
    false
  end

  def readable_image?(img)
    return readable_blob?(img) if img.is_a?(String)
    return true unless img.respond_to?(:tempfile)

    FastImage.size(img.tempfile, raise_on_failure: true)
    true
  rescue FastImage::FastImageException
    false
  end

  # A photo named by signed id: one the proposal already has is not read again; any other stored file is read
  # and must be an image.
  def readable_blob?(signed_id)
    blob = ActiveStorage::Blob.find_signed(signed_id)
    return false unless blob
    return true if stored_photo_blob_ids.include?(blob.id)

    blob.open { |file| FastImage.size(file, raise_on_failure: true) }
    true
  rescue FastImage::FastImageException, ActiveStorage::FileNotFoundError
    false
  end

  def stored_photo_blob_ids
    @stored_photo_blob_ids ||= ActiveStorage::Attachment.where(record: @project_proposal, name: 'photos').pluck(:blob_id)
  end

  MAX_NEW_IMAGES = 5

  # The legacy images field: at most five are taken.
  def new_images
    Array(uploads_param(:images)).first(MAX_NEW_IMAGES)
  end

  def attach_new_photos
    new_images.each { |img| @project_proposal.photos.attach(img) }
  end

  def uploaded_files
    Array(uploads_param(:files)).select { |f| f.respond_to?(:original_filename) }
  end

  # New files are checked with the model's rules (sniffed type and size) before anything is
  # saved or removed. If any is refused, the whole edit is refused and the files are named.
  def new_files_acceptable?
    refused = uploaded_files.reject { |f| @project_proposal.sniffed_upload_problems(:project_files, f).empty? }
    return true if refused.empty?

    @refused_files_alert =
      "The project proposal was not saved because the type or size of these files is not allowed: #{truncated_filenames(refused.map(&:original_filename))}."
    @project_proposal.errors.add(:project_files, @refused_files_alert)
    false
  end

  # Both checks always run, so every problem is reported.
  def new_uploads_acceptable?
    photos_ok = new_photos_readable?
    files_ok = new_files_acceptable?
    photos_ok && files_ok
  end

  # Returns false when the model refuses a file the pre-check let through; the caller rolls back.
  def attach_new_files
    files = uploaded_files
    return true if files.empty? || @project_proposal.project_files.attach(*files)

    reasons = @project_proposal.errors[:project_files].dup
    @project_proposal.errors.delete(:project_files)
    @refused_files_alert = "The project proposal was not saved. #{truncated_error_messages(reasons)}"
    @project_proposal.errors.add(:project_files, @refused_files_alert)
    false
  end

  MAX_FLASH_FILENAMES = 5
  MAX_FLASH_FILENAME_LENGTH = 40

  # Names every cause of a refused create or edit. Refused files come first, in the upload check's own words,
  # followed by any other cause (an unreadable photo, a failed validation); with no refused files, `key` leads.
  def refused_alert(key)
    return validation_message(@project_proposal, key) unless @refused_files_alert

    others = @project_proposal.errors.reject { |e| e.attribute == :project_files && e.message == @refused_files_alert }
    [@refused_files_alert, others.map(&:full_message).to_sentence].compact_blank.join(' ')
  end

  # The flash lives in the 4 KB cookie session, so names are shortened and capped.
  def truncated_filenames(names)
    shown = names.first(MAX_FLASH_FILENAMES).map { |n| n.to_s.truncate(MAX_FLASH_FILENAME_LENGTH) }
    extra = names.size - shown.size
    shown.join(', ') + (extra.positive? ? " and #{extra} more" : '')
  end

  def truncated_error_messages(messages)
    messages.first(3).map { |m| m.to_s.truncate(120) }.join('; ').presence || 'Some files could not be uploaded.'
  end

  def set_project_proposal
    @project_proposal = ProjectProposal.find_by_param(params[:id])
    return if @project_proposal

    redirect_to project_proposals_path, alert: 'Project proposal not found'
  end

  def require_visible_proposal
    return if @project_proposal.approved? || owner_or_admin?(@project_proposal)

    redirect_to project_proposals_path,
                alert: 'You are not allowed to access this pending project proposal.'
  end

  # Bare ids, stale titles and the old "<id>.<title>" form of a page address are moved to the
  # current address, keeping the query string. The old dotted form can never be current again, so
  # its move is permanent; a stale title or bare id is temporary, because titles change back.
  # Other requests are answered as they are.
  def redirect_to_canonical_url
    return unless request.get? && request.format.html?
    return if params[:id] == @project_proposal.to_param

    path = action_name == 'edit' ? edit_project_proposal_path(@project_proposal) : project_proposal_path(@project_proposal)
    path += "?#{request.query_string}" if request.query_string.present?
    redirect_to path, status: params[:id].include?('.') ? :moved_permanently : :found
  end

  def project_proposal_params
    permitted = [
      :title,
      :description,
      :youtube_link,
      :username,
      :email,
      :client,
      :client_type,
      :client_interest,
      :client_background,
      :supervisor_background,
      :equipments,
      :project_type,
      :project_cost,
      :prototype_cost,
      :past_experiences,
      { area: [], categories: [], photos: [], project_files: [] }
    ]

    permitted += %i[season year] if current_user&.admin?

    params.require(:project_proposal).permit(permitted)
  end

  # A create or an edit is applied in this order, so a failure can only happen before anything is removed:
  # new photos and files are checked; then, in one transaction, the proposal is validated and saved,
  # categories are replaced and new uploads attached; only after that commits are the attachments
  # the user asked to remove purged. A purge deletes the stored file and cannot be rolled back, so
  # it runs last (synchronously, so the page shows the result).
  def apply_edit(attributes)
    return false unless new_uploads_acceptable?

    removals = marked_attachments
    saved = ProjectProposal.transaction do
      next false unless @project_proposal.update_with_categories(attributes, project_proposal_params[:categories])

      @project_proposal.store_id_slug!
      attach_new_photos
      raise ActiveRecord::Rollback unless attach_new_files

      true
    end
    return false unless saved

    removals.each(&:purge)
    true
  end

  # A refused edit shows the submitted values in the form, as a failed validation does; nothing is saved
  # or removed. A rolled-back transaction leaves the unsaved changes in memory (the new title, attachments
  # that were never stored), so the record is read from the database again before the values are assigned.
  # New uploads were not stored, so they are not shown again.
  def refuse_edit(attributes)
    @project_proposal.reload
    @project_proposal.assign_attributes(attributes.except(:photos, :project_files))
  end

  # A refused create shows the submitted values in a new, blank form that keeps the reasons it was refused. The
  # refused record is not reused: after a rolled-back transaction it can still look stored and hold attachments
  # that were never stored. New uploads are not shown again.
  def refuse_create(attributes)
    refused = @project_proposal
    @project_proposal = ProjectProposal.new(attributes.except(:photos, :project_files))
    @project_proposal.user_id = refused.user_id
    @project_proposal.errors.merge!(refused.errors)
  end

  def project_join_params
    params.permit(:project_proposal_id)
  end

  # Linked repositories the viewer may see: every public one, plus private ones
  # that pass the private-repository gate (repository_unlocked?: admin, staff,
  # owner/member, or a password entered this session). Same predicate as the
  # repository page, so the two cannot drift.
  def viewable_linked_repositories
    linked = @project_proposal.repositories
    unlocked_private_ids =
      linked.where(share_type: 'private').select { |repo| repository_unlocked?(repo) }.map(&:id)
    linked.where(share_type: 'public').or(linked.where(id: unlocked_private_ids))
  end

  def sort_order
    case params[:sort]
    when 'newest'
      %i[created_at desc]
    when 'most_likes'
      %i[like desc]
    when 'most_makes'
      %i[make desc]
    when 'recently_updated'
      %i[updated_at desc]
    else
      %i[created_at desc]
    end
  end
end
