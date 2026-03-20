class LearningModule < ApplicationRecord
  include Filterable
  belongs_to :training, optional: true

  # these are conflicting with models with the same name, remove those first
  # before renaming to something more sensible.
  has_many_attached :photos # was: has_many :photos
  has_many_attached :project_files # was: has_many :repo_files
  has_many_attached :videos # was: has_many :videos

  has_many :learning_module_tracks, dependent: :destroy

  validates :title, presence: { message: 'A title is required.' }
  validate :uniqueness
  before_save :capitalize_title
  before_create :set_order

  scope :filter_by_level, ->(level) { where(level: level) }

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
