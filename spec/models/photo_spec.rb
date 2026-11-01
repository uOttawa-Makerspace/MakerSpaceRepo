require "rails_helper"

RSpec.describe Photo, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:repository).without_validating_presence }
      it { should belong_to(:proficient_project).without_validating_presence }
      it { should belong_to(:project_proposal).without_validating_presence }
    end

    context "has_one_attached" do
      it "has video attached" do
        photo = create(:photo)
        expect(photo.image).to be_attached
      end

      it "invalid image attached" do
        photo = build(:photo, :with_invalid_image)
        expect(photo.valid?).to be_falsey
      end
    end
  end

  # M67: the upload allow-list is pinned by content, not by one fake file.
  describe "image content-type allow-list" do
    def photo_with(name, type, bytes)
      build(:photo, image: FilesTestHelper.send(:in_memory, name, type, bytes))
    end

    it "accepts jpeg, png, gif and x-icon" do
      accepted = {
        "a.jpg" => ["image/jpeg", "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01#{"\x00" * 32}".b],
        "a.png" => ["image/png", File.binread(Rails.root.join("spec/support/assets/test.png"))],
        "a.gif" => ["image/gif", "GIF89a\x01\x00\x01\x00\x80\x00\x00#{"\x00" * 16}".b]
      }
      accepted.each do |name, (type, bytes)|
        photo = photo_with(name, type, bytes)
        expect(photo).to be_valid, "#{name} (#{photo.image.blob.content_type}): #{photo.errors.full_messages}"
      end
    end

    # ActiveStorage sniffs a real .ico as image/vnd.microsoft.icon, which is NOT
    # in the allow-list, so a real icon upload is refused; only a blob already typed
    # image/x-icon (identify: false) passes.
    it "accepts a blob typed image/x-icon and refuses a sniffed .ico" do
      ico = "\x00\x00\x01\x00\x01\x00\x10\x10#{"\x00" * 24}".b
      typed = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(ico), filename: "a.ico",
                                                     content_type: "image/x-icon", identify: false)
      expect(build(:photo, image: typed)).to be_valid
      expect(photo_with("a.ico", "image/x-icon", ico)).not_to be_valid
    end

    it "refuses text/html, application/pdf and svg uploads" do
      refused = {
        "page.html" => ["text/html", "<html><script>alert(1)</script></html>".b],
        "doc.pdf" => ["application/pdf", File.binread(Rails.root.join("spec/support/assets/RepoFile1.pdf"))],
        "pic.svg" => ["image/svg+xml", "<svg xmlns='http://www.w3.org/2000/svg'><script>1</script></svg>".b]
      }
      refused.each do |name, (type, bytes)|
        photo = photo_with(name, type, bytes)
        expect(photo).not_to be_valid, "#{name} (#{photo.image.blob.content_type}) should be refused"
        expect(photo.errors[:image]).to be_present
      end
    end
  end
end
