# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Skip link and focus ring", type: :system do
  def outline_style(script_target)
    page.evaluate_script("getComputedStyle(#{script_target}).outlineStyle")
  end

  it "is the first tab stop, shows on focus and moves focus to the main content" do
    visit root_path

    page.send_keys(:tab)
    link = page.find("a.skip-link", match: :first)
    expect(page.evaluate_script("document.activeElement.classList.contains('skip-link')")).to be true
    expect(link).to be_visible

    page.send_keys(:enter)
    expect(page.evaluate_script("document.activeElement.id")).to eq("main-content")
    expect(outline_style("document.activeElement")).to eq("none")
  end

  it "draws no outline on main after a mouse click on plain content" do
    visit root_path

    page.find("main#main-content h1, main#main-content p", match: :first).click
    expect(outline_style("document.getElementById('main-content')")).to eq("none")
  end

  it "draws the focus ring on a link reached by keyboard but not by mouse" do
    visit login_path

    page.find("a.navbar-brand").click
    visit login_path
    page.send_keys(:tab, :tab)
    expect(page.evaluate_script("document.activeElement.matches(':focus-visible')")).to be true
    expect(page.evaluate_script("getComputedStyle(document.activeElement).outlineWidth")).to eq("3px")
    expect(outline_style("document.activeElement")).to eq("solid")
  end
end
