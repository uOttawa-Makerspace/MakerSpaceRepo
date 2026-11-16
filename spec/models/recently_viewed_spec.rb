# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecentlyViewed do
  it "keeps entries whose link is a path on this site" do
    raw = '{"/user/1":"One","/user/2.slug":"Two"}'
    expect(described_class.parse(raw)).to eq("/user/1" => "One", "/user/2.slug" => "Two")
  end

  it "drops other links and entries without a text title" do
    raw = JSON.generate("//host/x" => "a", "javascript:alert(1)" => "b", "/\\host" => "c", "/ x" => "d", "/ok" => 5, "/fine" => "e")
    expect(described_class.parse(raw)).to eq("/fine" => "e")
  end

  it "is empty for a missing cookie, broken JSON or JSON that is not an object" do
    [nil, "", "not json", "[1,2]"].each { |raw| expect(described_class.parse(raw)).to eq({}) }
  end
end
