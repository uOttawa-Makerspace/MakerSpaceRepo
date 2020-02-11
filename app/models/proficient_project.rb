class ProficientProject < ActiveRecord::Base
  has_and_belongs_to_many :users
  belongs_to :training
  has_many :photos
  has_many :repo_files
  has_many :videos
end
