# frozen_string_literal: true

module CertificationsHelper
  def certification_status(level)
    div =
      Proc.new do |color, level|
        "<span style='color: #{color}'>#{level}</span>"
      end
    if level.eql?("Advanced")
      div.call("red", "🦅 Advanced")
    elsif level.eql?("Intermediate")
      div.call("#969600", "🦩 Intermediate")
    elsif level.eql?("Beginner")
      div.call("green", "🦆 Beginner")
    else
      div.call("black", "🐥 Newbie")
    end
  end
end
