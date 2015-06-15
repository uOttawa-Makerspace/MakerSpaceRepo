class Comment < ActiveRecord::Base
  belongs_to :user
  belongs_to :repository

  has_many :upvotes, dependent: :destroy
  validates :content, presence: true
end
