# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::TrackGenreDeriver do
  let(:metal) { create(:genre, name: "metal") }
  let(:new_age) { create(:genre, name: "new age") }
  let(:slayer) { create(:artist, :with_genres, genres: [metal]) }

  describe "#by_track" do
    it "copies each credited artist's genres onto the track" do
      enya = create(:artist, :with_genres, genres: [new_age])
      track = create(:track, :with_artists, artists: [slayer, enya])

      described_class.new.by_track([track.id])

      expect(track.genres.pluck(:name)).to contain_exactly("metal", "new age")
    end

    it "writes nothing for an artist that has no genres yet" do
      track = create(:track, :with_artists, artist_count: 1)

      expect { described_class.new.by_track([track.id]) }.not_to change(TrackGenre, :count)
    end

    it "leaves tracks outside the given ids untouched" do
      create(:track, :with_artists, artists: [slayer])
      other = create(:track, :with_artists, artists: [slayer])

      described_class.new.by_track([other.id])

      expect(TrackGenre.count).to eq(1)
      expect(other.genres).to contain_exactly(metal)
    end

    it "is idempotent" do
      track = create(:track, :with_artists, artists: [slayer])

      2.times { described_class.new.by_track([track.id]) }

      expect(TrackGenre.where(track: track).count).to eq(1)
    end

    it "does nothing when given no ids" do
      expect { described_class.new.by_track([]) }.not_to change(TrackGenre, :count)
    end

    it "preserves a user-sourced genre on the same track and genre" do
      track = create(:track, :with_artists, artists: [slayer])
      create(:track_genre, track: track, genre: metal, source: :user, confidence: 0.5)

      described_class.new.by_track([track.id])

      expect(TrackGenre.where(track: track, genre: metal).pluck(:source))
        .to contain_exactly("user", "spotify")
    end
  end

  describe "#by_artist" do
    it "backfills every track credited to the artist" do
      first = create(:track, :with_artists, artists: [slayer])
      second = create(:track, :with_artists, artists: [slayer])

      described_class.new.by_artist([slayer.id])

      expect(first.genres).to contain_exactly(metal)
      expect(second.genres).to contain_exactly(metal)
    end

    it "does not touch tracks by other artists" do
      other = create(:track, :with_artists, artist_count: 1)

      described_class.new.by_artist([slayer.id])

      expect(other.genres).to be_empty
    end
  end
end
