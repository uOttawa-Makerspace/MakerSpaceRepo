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

  def approval_status
    case self.approved
    when 0 then "No"
    when 1 then "Yes"
    when nil then "Not validated"
    end
  end

end
