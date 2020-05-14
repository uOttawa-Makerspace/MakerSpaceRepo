class Video < ActiveRecord::Base
  include Sidekiq::Worker
  belongs_to :proficient_project
  has_attached_file :video, :styles => {
      :medium => { :geometry => "640x480", :format => 'flv' },
      :thumb => { :geometry => "100x100#", :format => 'jpg', :time => 10 }
  }, :processors => [:transcoder]
  validates_attachment_content_type :video, :content_type => /\Avideo\/.*\Z/

  #TODO: Needs to be updated
  # This was added in an attempt to use sidekiq to upload videos
  def perform(video, proficient_project_id)
    Video.create(video: video, proficient_project_id: proficient_project_id)
  end


  BUCKET_NAME = ENV.fetch('S3_BUCKET_NAME', "makerspace-testing-for-real")

  DIRECT_UPLOAD_URL_FORMAT = %r{\Ahttps:\/\/#{BUCKET_NAME}\.s3\.amazonaws\.com\/(?<path>.+\/(?<filename>.+))\z}.freeze
  # DIRECT_UPLOAD_URL_FORMAT = %r{\Ahttps:\/\/s3\.amazonaws\.com\/#{BUCKET_NAME}\/(?<path>uploads\/.+\/(?<filename>.+))\z}.freeze
  #   "https://s3.amazonaws.com/myapp-development/uploads/92a7d2c5-83de-47ad-981c-c6e391531a0e/foo.jpg"
  validates :direct_upload_url, presence: true, format: { with: DIRECT_UPLOAD_URL_FORMAT }

  before_create :set_video_attributes
  # after_create :queue_finalize_and_cleanup

  # Store an unescaped version of the escaped URL that Amazon returns from direct upload.
  def direct_upload_url=(escaped_url)
    write_attribute(:direct_upload_url, (CGI.unescape(escaped_url) rescue nil))
  end

  # Update the document upload and manually re-process
  def update_file(params)
    self.processed = false
    self.attributes = params
    set_upload_attributes
    save!
    Video.delay.finalize_and_cleanup(id)
  end

  # Determines if file requires post-processing (image resizing, etc)
  def post_process_required?
    %r{^(image|(x-)?application)/(bmp|gif|jpeg|jpg|pjpeg|png|x-png)$}.match(upload_content_type).present?
  end

  # Final upload processing step:
  #
  # 1) If the file does not require processing, manually copy direct uplaod to
  #   the location that Paperclip expects, saving transfer time/cost.
  #   If the file requires post-processing, set the direct_upload_url as the document's remote source,
  #   which instantiates download, process, and re-upload of the file via Paperclip callbacks.
  # 2) Flag document as processed
  # 3) Delete the temp upload from s3.
  #
  # @see http://docs.aws.amazon.com/AmazonS3/latest/dev/CopyingObjectUsingRuby.html
  def self.finalize_and_cleanup(id)
    document = Document.find(id)
    direct_upload_url_data = DIRECT_UPLOAD_URL_FORMAT.match(document.direct_upload_url)
    s3 = Aws::S3::Client.new(region: ENV.fetch('AWS_REGION', "us-west-2"))

    if document.post_process_required?
      document.upload = URI.parse(URI.escape(document.direct_upload_url))
    else
      paperclip_file_path = "documents/uploads/#{id}/original/#{direct_upload_url_data[:filename]}"
      s3.buckets[BUCKET_NAME].objects[paperclip_file_path].copy_from(direct_upload_url_data[:path])
    end

    document.processed = true
    document.save

    s3.buckets[BUCKET_NAME].objects[direct_upload_url_data[:path]].delete
  end

  protected

  # Optional: Set attachment attributes from the direct upload instead of original upload callback params
  # @note Retry logic handles occasional S3 "eventual consistency" lag.
  def set_video_attributes
    tries ||= 5
    direct_upload_url_data = DIRECT_UPLOAD_URL_FORMAT.match(direct_upload_url)
    s3 = Aws::S3::Client.new(region:'us-west-2', credentials: Aws::Credentials.new('AKIA34PB766HVB2UJ4YZ', '5Qg/ZF0S+2JjHQ8bjce6eagll8ZosF5xulqikiPJ'))
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
    Document.delay.finalize_and_cleanup(id)
  end
end
