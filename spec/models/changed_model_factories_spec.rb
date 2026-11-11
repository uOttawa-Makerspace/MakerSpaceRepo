require "rails_helper"

# Models whose validations were tightened must still get a valid record from their factories.
RSpec.describe "factories for models with presence and parent rules" do
  %i[proficient_project project_requirement project_kit video].each do |name|
    it "builds a valid #{name}" do
      expect { create(name) }.not_to raise_error
    end
  end

  it "builds a valid project requirement between two different projects" do
    requirement = create(:project_requirement)

    expect(requirement.proficient_project).not_to eq(requirement.required_project)
  end

  it "builds a valid video attached to a learning module only" do
    expect { create(:video, proficient_project: nil, learning_module: create(:learning_module)) }.not_to raise_error
  end
end
