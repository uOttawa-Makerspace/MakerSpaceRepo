# frozen_string_literal: true

class ProjectProposal < ApplicationRecord
  belongs_to :user
  belongs_to :admin, class_name: 'User', foreign_key: 'admin_id'
  has_many :categories,     dependent: :destroy
  has_many :project_joins,  dependent: :destroy
  has_many :repositories
  has_many :photos, dependent: :destroy
  has_many :repo_files, dependent: :destroy

  scope :approved, -> { where(approved: 1) }

  validates :title,
            format: { with: /\A[-a-zA-ZÀ-ÿ\d\s]*\z/, message: 'Invalid project title' },
            presence: { message: 'Project title is required.' }

  validates :email,
            presence: { message: 'Your email is required.' }

  before_save do
    self.youtube_link = nil if youtube_link && !YoutubeID.from(youtube_link)
  end

  before_create do
    self.slug = title.downcase.gsub(/[^0-9a-z ]/i, '').gsub(/\s+/, '-')
  end

  before_update do
    self.slug = id.to_s + '.' + title.downcase.gsub(/[^0-9a-z ]/i, '').gsub(/\s+/, '-')
  end

  def self.filter_by_attribute(value)
    if value
      if value == 'search='
        default_scoped
      else
        value = value.split('=').last.gsub('+', ' ').gsub('%20', ' ')
        where("LOWER(users.name) like LOWER(?) OR
               LOWER(users.username) like LOWER(?) OR
               LOWER(client) like LOWER(?) OR
               LOWER(title) like LOWER(?)",
               "%#{value}%", "%#{value}%", "%#{value}%", "%#{value}%")
      end
    else
      default_scoped
    end
  end

  def approval_status
    case self.approved
    when 0 then "No"
    when 1 then "Yes"
    when nil then "Not validated"
    end
  end

end
