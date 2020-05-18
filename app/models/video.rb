class Video < ActiveRecord::Base
  include Sidekiq::Worker
  belongs_to :proficient_project
  scope :processed, -> {where(processed: true)}

  has_attached_file :video
  # Large files are not pratical to transcode
  # , :styles => {
  #     :medium => { :geometry => "640x480", :format => 'flv' },
  #     :thumb => { :geometry => "100x100#", :format => 'jpg', :time => 10 }
  # }, :processors => [:transcoder]

  Rails.env.eql?("development") ? BUCKET_NAME = ENV.fetch('S3_BUCKET_NAME', "makerspace-testing-for-real") : BUCKET_NAME = Rails.application.secrets.s3_bucket_name
  DIRECT_UPLOAD_URL_FORMAT = %r{\Ahttps:\/\/#{BUCKET_NAME}\.s3\.amazonaws\.com\/(?<path>.+\/(?<filename>.+))\z}.freeze

  validates_attachment_content_type :video, :content_type => /\Avideo\/.*\Z/
  validates :direct_upload_url, presence: true, format: { with: DIRECT_UPLOAD_URL_FORMAT }
  # before_create :set_video_attributes
  after_create :queue_finalize_and_cleanup

  def perform(video_id)
    Video.finalize_and_cleanup(video_id)
  end

  # Store an unescaped version of the escaped URL that Amazon returns from direct upload.
  def direct_upload_url=(escaped_url)
    write_attribute(:direct_upload_url, (CGI.unescape(escaped_url) rescue nil))
  end

  def self.finalize_and_cleanup(id)
    document = Video.find(id)
    direct_upload_url_data = DIRECT_UPLOAD_URL_FORMAT.match(document.direct_upload_url)
    s3 = Aws::S3::Client.new
    document.video = URI.parse(URI.escape(document.direct_upload_url)).open
    document.processed = true
    document.save
    s3.delete_object(bucket: BUCKET_NAME, key: direct_upload_url_data[:path])
  end

  protected

  # Retry logic handles occasional S3 "eventual consistency" lag.
  def set_video_attributes
    tries ||= 5
    direct_upload_url_data = DIRECT_UPLOAD_URL_FORMAT.match(direct_upload_url)
    s3 = Aws::S3::Client.new
    direct_upload_head = s3.get_object(bucket: BUCKET_NAME, key: direct_upload_url_data[:path])
    self.video_file_name     = direct_upload_url_data[:filename]
    self.video_file_size     = direct_upload_head.content_length
    self.video_content_type  = direct_upload_head.content_type
    self.video_updated_at    = direct_upload_head.last_modified
  rescue Aws::S3::Errors::NoSuchKey => e
    tries -= 1
    if tries > 0
      sleep(3)
      retry
    else
      raise e
    end
  end

  # Queue final file processing
  def queue_finalize_and_cleanup
    Video.perform_async(id)
  end
end
