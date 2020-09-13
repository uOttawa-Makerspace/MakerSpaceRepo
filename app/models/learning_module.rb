class LearningModule < ApplicationRecord
  include Filterable
  belongs_to :training
  has_many :photos,                     dependent: :destroy
  has_many :repo_files,                 dependent: :destroy
  has_many :videos,                     dependent: :destroy
  has_many :project_kits,               dependent: :destroy

  # TODO: Do we want to include requirements, badges and more ?
  # has_and_belongs_to_many :users
  # belongs_to :badge_template
  # has_many :project_requirements,       dependent: :destroy
  # has_many :required_projects, through: :project_requirements
  # has_many :inverse_project_requirements, class_name: 'ProjectRequirement', foreign_key: 'required_project_id'
  # has_many :inverse_required_projects, through: :inverse_project_requirements, source: :proficient_project
  # has_many :cc_moneys,                  dependent: :destroy
  # has_many :order_items,                dependent: :destroy
  # has_many :badge_requirements,         dependent: :destroy

  validates :title, presence: { message: 'A title is required.' }, uniqueness: { message: 'Title already exists' }
  before_save :capitalize_title

  scope :filter_by_level, ->(level) { where(level: level) }
  scope :filter_by_proficiency, ->(proficient) { where(proficient: proficient) }

  def capitalize_title
    self.title = title.capitalize
  end

  def self.filter_by_attribute(attribute, value)
    if attribute == 'level'
      filter_by_level(value)
    elsif attribute == 'category'
      joins(:training).where(trainings: { name: value })
    elsif attribute == 'search'
      where("LOWER(title) like LOWER(?) OR
                 LOWER(level) like LOWER(?) OR
                 LOWER(description) like LOWER(?)", "%#{value}%", "%#{value}%", "%#{value}%")
    elsif attribute == 'proficiency'
      filter_by_proficiency(value)
    elsif attribute == 'price'
      bool = true if value.eql?('Paid')
      bool = false if value.eql?('Free')
      where(proficient: bool)
    else
      self
    end
  end

  # TODO : Do we use badges for learning modules ?
  # def delete_all_badge_requirements
  #   badge_requirements.destroy_all
  # end
  #
  # def create_badge_requirements(badge_requirements_id)
  #   badge_requirements_id.each do |requirement_id|
  #     badge_template = BadgeTemplate.find_by(id: requirement_id)
  #     badge_requirements.create(badge_template: badge_template) if badge_template
  #   end
  # end
end
