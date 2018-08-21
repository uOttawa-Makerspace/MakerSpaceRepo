class ProjectProposal < ActiveRecord::Base
  has_many   :categories,     dependent: :destroy
  belongs_to  :user
  has_and_belongs_to_many   :project_joins, :uniq => true

  validates :title,
            format:     { with:    /\A[-a-zA-Z\d\s]*\z/, message: "Invalid project title" },
            presence:   { message: "Project title is required."}

  validates :email,
            presence: { message: "Your email is required." }

  before_save do
    if self.youtube_link && !YoutubeID.from(self.youtube_link)
      self.youtube_link = nil
    end
  end
end
