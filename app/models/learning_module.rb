class LearningModule < ApplicationRecord
  include Filterable
  belongs_to :training, optional: true

  # these are conflicting with models with the same name, remove those first
  # before renaming to something more sensible.
  has_many_attached :photos # was: has_many :photos
  has_many_attached :project_files # was: has_many :repo_files
  has_many_attached :videos # was: has_many :videos

  # SCORM packages are a zip file
  has_one_attached :scorm_package
  # If scorm package changes, update extraction or purge
  after_save :process_scorm_package,
             if: -> { attachment_changes.key?('scorm_package') }

  # The unzipped files are attached to this model here. Need to clear if the
  # scorm package changes
  has_many_attached :scorm_package_files

  enum :scorm_status,
       { pending: 0, processing: 1, ready: 2, failed: 3 },
       prefix: :scorm

  has_many :learning_module_tracks, dependent: :destroy

  validates :title, presence: { message: 'A title is required.' }
  validate :uniqueness
  before_save :capitalize_title
  before_create :set_order

  scope :filter_by_level, ->(level) { where(level: level) }

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

  def process_scorm_package
    if scorm_package.attached?
      update!(scorm_status: :processing)
      ExtractScormJob.perform_later(id)
    else
      scorm_package_files.purge
    end
  end

  def uniqueness
    if LearningModule
         .where(title: self.title, training_id: self.training_id)
         .where.not(id: self.id)
         .count > 0
      self.errors.add(:title, 'Title already exists')
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
