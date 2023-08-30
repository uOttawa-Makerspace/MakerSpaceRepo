class KeyCertification < ApplicationRecord
  belongs_to :user, optional: true
  has_one_attached :pdf_file_1, dependent: :destroy
  has_one_attached :pdf_file_2, dependent: :destroy
  has_one_attached :pdf_file_3, dependent: :destroy
  has_one_attached :pdf_file_4, dependent: :destroy
  has_one_attached :pdf_file_5, dependent: :destroy
  has_one_attached :pdf_file_6, dependent: :destroy
  has_one_attached :pdf_file_7, dependent: :destroy
  has_one_attached :pdf_file_8, dependent: :destroy
  has_one_attached :pdf_file_9, dependent: :destroy

  TOTAL_NUMBER_OF_FILES = 9
  NUMBER_OF_STAFF_FILES = 8
  NUMBER_OF_SUPERVISOR_FILES = TOTAL_NUMBER_OF_FILES - NUMBER_OF_STAFF_FILES

  FILE_NAMES = %w[
    WHMIS
    worker-health-and-safety-awareness
    violence-prevention
    respect-in-the-workplace
    accessibility-standards-for-customer-service
    the-code-and-the-AODA
    dry-lab-risk-management
    health-and-safety-roles-and-responsibilities
    supervisor-health-and-safety-awareness
  ]

  FILE_URLS = %w[
    https://www.uottawa.ca/about-us/administration-services/office-risk-management/training/whmis/lab/module-1
    https://web47.uottawa.ca/en/lrs/node/1481
    https://web47.uottawa.ca/en/lrs/node/1847
    https://web47.uottawa.ca/en/lrs/node/1602
    https://web47.uottawa.ca/en/lrs/node/1071
    https://web47.uottawa.ca/en/lrs/node/2398
    https://web47.uottawa.ca/en/lrs/node/38516
    https://web47.uottawa.ca/en/lrs/node/38274
    https://web47.uottawa.ca/en/lrs/node/2082
  ]

  validates :user, presence: true

  validate :validate_files

  def generate_filename(file_number)
    "#{user.name.parameterize}-#{KeyCertification::FILE_NAMES[file_number - 1]}.pdf"
  end

  def attach_pdf_file(file_number, uploaded_file)
    file_name = "pdf_file_#{file_number}"
    send(file_name).attach(uploaded_file)
    send(file_name).blob.update(filename: generate_filename(file_number))
  end

  def get_key_certs_attached
    count = 0
    (1..NUMBER_OF_STAFF_FILES).each do |i|
      file_param = "pdf_file_#{i}"
      count += 1 if self.send(file_param).attached?
    end
    count
  end

  def get_supervisor_certs_attached
    count = 0
    ((NUMBER_OF_STAFF_FILES + 1)..TOTAL_NUMBER_OF_FILES).each do |i|
      file_param = "pdf_file_#{i}"
      count += 1 if self.send(file_param).attached?
    end
    count
  end

  private

  def validate_files
    (1..TOTAL_NUMBER_OF_FILES).each do |i|
      file_param = "pdf_file_#{i}"
      if self.send(file_param).attached? &&
           !self.send(file_param).content_type.in?(%w[application/pdf])
        errors.add(file_param.to_sym, "must be a PDF file")
      end
    end
  end
end
