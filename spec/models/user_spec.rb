# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  describe "factory" do
    it "has a valid factory" do
      expect(build(:user)).to be_valid
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:password) }
  end
end
