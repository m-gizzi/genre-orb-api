# frozen_string_literal: true

require "rails_helper"

RSpec.describe Genre do
  describe "name normalization" do
    it "lowercases the name" do
      genre = create(:genre, name: "ROCK")
      expect(genre.name).to eq("rock")
    end

    it "strips leading and trailing whitespace" do
      genre = create(:genre, name: "  rock  ")
      expect(genre.name).to eq("rock")
    end

    it "collapses internal whitespace" do
      genre = create(:genre, name: "death   metal")
      expect(genre.name).to eq("death metal")
    end

    it "handles mixed case and whitespace" do
      genre = create(:genre, name: "  Progressive   ROCK  ")
      expect(genre.name).to eq("progressive rock")
    end
  end
end
