require "rails_helper"

RSpec.describe RepoFile, type: :model do
  describe "Association" do
    context "belongs_to" do
      it { should belong_to(:repository).without_validating_presence }
      it { should belong_to(:proficient_project).without_validating_presence }
      it { should belong_to(:project_proposal).without_validating_presence }
    end
  end

  describe "Validation" do
    context "has_one_attached" do
      it "has file attached" do
        file = create(:repo_file)
        expect(file.file).to be_attached
      end

      it "valid file attached for repo" do
        file = build(:repo_file, :in_repository, :with_invalid_file)
        expect(file.valid?).to be_truthy
      end

      # The trait is called "invalid", but an STL is on the proficient-project allow-list,
      # so this pins that it is ACCEPTED there (refusals are pinned further down).
      it "accepts an STL file in a proficient project (allow-listed, despite the trait name)" do
        file = build(:repo_file, :in_proficient_project, :with_invalid_file)
        expect(file.valid?).to be(true), file.errors.full_messages.to_sentence
      end
    end
  end

  # Regression from A9 (D-C06): the proficient-project allow-list held the
  # extensions ".doc"/".docx" instead of MIME types, so no real Word file matched.
  describe "Word documents in a proficient project" do
    require "zip"

    let(:project) { create(:proficient_project) }

    def minimal_docx
      Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("[Content_Types].xml")
        zip.write('<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
        zip.put_next_entry("_rels/.rels")
        zip.write('<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
        zip.put_next_entry("word/document.xml")
        zip.write('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>hi</w:t></w:r></w:p></w:body></w:document>')
      end.string
    end

    # the OLE2 compound-file header every legacy .doc starts with
    def minimal_doc
      "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1".b + ("\x00" * 504)
    end

    def exe
      "MZ".b + "\x90\x00\x03\x00".b + ("\x00" * 60)
    end

    def repo_file(filename, bytes, declared)
      build(:repo_file, proficient_project: project, file: { io: StringIO.new(bytes), filename: filename, content_type: declared })
    end

    ["application/octet-stream", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/zip"].each do |declared|
      it "accepts a real .docx declared as #{declared}" do
        expect(repo_file("report.docx", minimal_docx, declared)).to be_valid
      end
    end

    ["application/octet-stream", "application/msword"].each do |declared|
      it "accepts a real .doc declared as #{declared}" do
        record = repo_file("report.doc", minimal_doc, declared)
        expect(record).to be_valid, record.errors.full_messages.to_sentence
      end
    end

    it "still refuses an executable named .docx or .doc" do
      %w[evil.docx evil.doc].each do |name|
        record = repo_file(name, exe, "application/msword")
        expect(record).not_to be_valid
        expect(record.errors[:file].to_sentence).to include("not allowed")
      end
    end

    it "still refuses an executable declared as a Word type, through the declared-type check too" do
      record = repo_file("evil.exe", exe, "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
      expect(record).not_to be_valid
    end

    it "keeps the listed MIME types, and no extension strings, in the allow-list" do
      expect(RepoFile::ALLOWED_CONTENT_TYPES).to include(
        "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      )
      expect(RepoFile::ALLOWED_CONTENT_TYPES.grep(/\A\./)).to be_empty
    end

    it "does not restrict repository files to Word (they use the denylist)" do
      record = build(:repo_file, :in_repository, file: { io: StringIO.new(minimal_docx), filename: "a.docx", content_type: "application/octet-stream" })
      expect(record).to be_valid
    end
  end
end
