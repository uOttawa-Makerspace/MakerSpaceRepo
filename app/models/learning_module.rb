class LearningModule < ApplicationRecord
  include Filterable
  belongs_to :training, optional: true

  # these are conflicting with models with the same name, remove those first
  # before renaming to something more sensible.
  has_many_attached :photos # was: has_many :photos
  has_many_attached :project_files # was: has_many :repo_files
  has_many_attached :videos # was: has_many :videos

  # Normalization runs before validation, but we still want to catch if something breaks
  normalizes :shortcut_name,
             with: ->(shortcut_name) do
               shortcut_name.strip.downcase.underscore.parameterize(
                 separator: '_'
               )
             end
  validates :shortcut_name, format: { with: /\A[a-zA-Z0-9_]+\z/ }, allow_blank: true
  validates :shortcut_name, uniqueness: { case_sensitive: false }

  enum :level,
       {
         # AKA 'no level'
         general: 'General',
         beginner: 'Beginner',
         intermediate: 'Intermediate',
         advanced: 'Advanced'
       },
       validate: true

  # SCORM packages are a zip file
  has_one_attached :scorm_package

  # Check if we need to reprocess package. We need the is_a? check because
  # sometimes no file is uploaded.
  before_save -> do
    new_blob = attachment_changes['scorm_package']
    @scorm_package_changed =
      new_blob.is_a?(ActiveStorage::Attached::Changes::CreateOne) &&
        !new_blob.blob.persisted?
    @scorm_package_cleared =
      new_blob.is_a?(ActiveStorage::Attached::Changes::DeleteOne)

    # Reset status to pending immediately when a new zip is uploaded
    if @scorm_package_changed
      self.scorm_status = :pending
      self.scorm_status_changed_at = Time.current
      self.scorm_error = nil
    end
  end

  # If scorm package changes, update extraction or purge File is available only
  # after commit, but change key is cleared after save. This would queue the
  # job, and the job is configured to run after commit succeeds
  # https://guides.rubyonrails.org/active_storage_overview.html#downloading-files
  # https://codewithrails.com/blog/rails-enqueue-after-transaction-commit/
  after_commit :process_scorm_package,
               on: %i[create update],
               if: -> { @scorm_package_changed || @scorm_package_cleared }
  # The unzipped files are attached to this model here. Need to clear if the
  # scorm package changes
  has_many_attached :scorm_package_files

  # Value to receive from the edit form
  attribute :scorm_enabled, :boolean, default: false
  after_initialize -> { self.scorm_enabled = scorm_package.attached? }

  enum :scorm_status,
       { pending: 0, processing: 1, ready: 2, failed: 3 },
       prefix: :scorm

  # A pending/processing extraction older than this has not finished (the job
  # never ran, or its worker died) and is treated as stalled.
  SCORM_STALL_AFTER = 15.minutes

  has_many :learning_module_tracks, dependent: :destroy

  validates :title, presence: true
  validate :uniqueness
  before_save :capitalize_title
  before_create :set_order

  scope :filter_by_level, ->(level) { where(level: level) }
  scope :ordered_by_level,
        -> do
          rank =
            levels.values.each_with_index.reduce(Arel::Nodes::Case.new(arel_table[:level])) do |node, (value, i)|
              node.when(value).then(i)
            end
          order(rank.else(0))
        end

  default_scope { order(:order) }

  def scorm_asset_url(relative_path)
    if relative_path.include?('..')
      raise ArgumentError, 'Path traversal detected'
    end

    Rails.application.routes.url_helpers.scorm_asset_learning_area_url(
      self,
      path: relative_path,
      host: Rails.application.credentials.host
    )
  end

  # The status column defaults to pending, so it only means something for a
  # module that has a package.
  def scorm_stalled?
    scorm_package.attached? && (scorm_pending? || scorm_processing?) &&
      (scorm_status_changed_at.nil? || scorm_status_changed_at < SCORM_STALL_AFTER.ago)
  end

  # Why the package is not usable, for people who manage the module.
  def scorm_problem
    return unless scorm_package.attached?

    if scorm_failed?
      scorm_error.presence || 'The package could not be processed.'
    elsif scorm_stalled?
      'Extraction did not finish. The background worker may not be running.'
    end
  end

  # Learner progress is accepted for a package that has been extracted, also
  # while a later upload is being re-extracted.
  def scorm_trackable?
    scorm_package.attached? && scorm_prefix.present?
  end

  def scorm_retryable?
    scorm_package.attached? && (scorm_failed? || scorm_stalled?)
  end

  # Starts a fresh extraction. A run that is still going on from before is
  # superseded: the extractor only publishes if its claim is still current.
  def retry_scorm_extraction
    return false unless scorm_retryable?

    update_columns(
      scorm_status: self.class.scorm_statuses[:pending],
      scorm_status_changed_at: Time.current,
      scorm_error: nil
    )
    ExtractScormJob.perform_later(id)
    true
  end

  def tracks_for_user(user)
    learning_module_tracks.find_by(user:)
  end

  def capitalize_title
    self.title = title.upcase_first
  end

  def self.filter_by_attribute(attribute, value)
    if attribute == 'level'
      filter_by_level(value)
    elsif attribute == 'category'
      joins(:training).where(trainings: { name: value })
    elsif attribute == 'search'
      sanitized = sanitize_sql_like(value)
      where(
        'LOWER(title) LIKE LOWER(?) OR
        LOWER(level) LIKE LOWER(?) OR
        LOWER(description) LIKE LOWER(?)',
        "%#{sanitized}%",
        "%#{sanitized}%",
        "%#{sanitized}%"
      )
    else
      self
    end
  end

  def extract_urls
    URI.extract(self.description)
  end

  def extract_valid_urls
    extract_urls.uniq.select do |url|
      uri = URI.parse(url)
      uri.host == 'wiki.makerepo.com' ||
        uri.host&.end_with?('.wiki.makerepo.com')
    rescue URI::InvalidURIError
      false
    end
  end

  private

  # Called when scorm package changes
  def process_scorm_package
    if scorm_package.attached?
      Rails.logger.info "Queued SCORM extract for learning module #{id}"
      # ExtractScorm purges files eventually.
      ExtractScormJob.perform_later(id)
    else
      # Package removed, delete files
      scorm_package_files.purge_later
    end
  end

  def uniqueness
    if LearningModule
         .where(title: self.title, training_id: self.training_id)
         .where.not(id: self.id)
         .count > 0
      errors.add(:title, :taken)
    end
  end

  def set_order
    self.order =
      (
        if LearningModule.maximum(:order).present?
          LearningModule.maximum(:order) + 1
        else
          0
        end
      )
  end
end
