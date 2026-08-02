# frozen_string_literal: true

require "rails_helper"

RSpec.describe LikedSongsPlaylist do
  describe "details managed by Spotify" do
    let(:liked) { create(:liked_songs_playlist) }

    it "rejects a rename" do
      liked.name = "My Favourites"

      expect(liked).not_to be_valid
      expect(liked.errors[:name]).to include("is managed by Spotify")
    end

    it "rejects a description" do
      liked.description = "Everything I love"

      expect(liked).not_to be_valid
      expect(liked.errors[:description]).to include("is managed by Spotify")
    end

    it "allows toggling sync" do
      expect(liked.update(sync_enabled: true)).to be(true)
    end

    it "allows the metadata fetch to restore the canonical name" do
      liked.update_columns(name: "Stale Name")

      liked.reload.name = described_class::CANONICAL_NAME

      expect(liked).to be_valid
    end

    it "allows clearing a stray description" do
      liked.update_columns(description: "Left over")

      liked.reload.description = nil

      expect(liked).to be_valid
    end

    it "does not block creation" do
      expect(build(:liked_songs_playlist)).to be_valid
    end
  end

  describe "#spotify_id" do
    it "is always nil" do
      expect(create(:liked_songs_playlist).spotify_id).to be_nil
    end
  end

  describe "one per user" do
    it "rejects a second Liked Songs playlist for the same user" do
      user = create(:user)
      create(:liked_songs_playlist, user: user)

      expect(build(:liked_songs_playlist, user: user)).not_to be_valid
    end
  end
end
