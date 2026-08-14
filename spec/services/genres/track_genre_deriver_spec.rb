# frozen_string_literal: true

require "rails_helper"

RSpec.describe Genres::TrackGenreDeriver do
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

  describe "multi-source attribution" do
    it "carries the artist_genre's source onto the track, not spotify" do
      artist = create(:artist, :with_genres, genres: [metal], genre_source: :lastfm, genre_confidence: 0.6)
      track = create(:track, :with_artists, artists: [artist])

      described_class.new.by_track([track.id])

      expect(TrackGenre.sole).to have_attributes(source: "lastfm", confidence: 0.6)
    end

    it "derives one row per source when several agree on a genre" do
      artist = create(:artist)
      %i[spotify musicbrainz lastfm].each do |source|
        create(:artist_genre, artist: artist, genre: metal, source: source)
      end
      track = create(:track, :with_artists, artists: [artist])

      described_class.new.by_track([track.id])

      expect(TrackGenre.where(track: track, genre: metal).pluck(:source))
        .to contain_exactly("spotify", "musicbrainz", "lastfm")
    end

    # Two artists carrying the same genre from the same source supply two rows for one
    # conflict target. Without DISTINCT ON, Postgres raises "ON CONFLICT DO UPDATE
    # command cannot affect row a second time".
    it "collapses two artists agreeing on a genre from the same source" do
      first = create(:artist, :with_genres, genres: [metal], genre_source: :lastfm, genre_confidence: 0.4)
      second = create(:artist, :with_genres, genres: [metal], genre_source: :lastfm, genre_confidence: 0.9)
      track = create(:track, :with_artists, artists: [first, second])

      expect { described_class.new.by_track([track.id]) }.to change(TrackGenre, :count).by(1)
    end

    it "keeps the stronger confidence when two artists agree" do
      first = create(:artist, :with_genres, genres: [metal], genre_source: :lastfm, genre_confidence: 0.4)
      second = create(:artist, :with_genres, genres: [metal], genre_source: :lastfm, genre_confidence: 0.9)
      track = create(:track, :with_artists, artists: [first, second])

      described_class.new.by_track([track.id])

      expect(TrackGenre.sole.confidence).to be_within(0.001).of(0.9)
    end

    # source is part of the conflict target, so a derived user row would land on the
    # genre a person set on that track by hand and overwrite its confidence.
    it "does not derive a user-curated artist genre onto their tracks" do
      artist = create(:artist, :with_genres, genres: [metal], genre_source: :user, genre_confidence: 0.3)
      track = create(:track, :with_artists, artists: [artist])

      expect { described_class.new.by_track([track.id]) }.not_to change(TrackGenre, :count)
    end

    it "leaves a hand-set track genre untouched while deriving the provider's" do
      artist = create(:artist)
      create(:artist_genre, artist: artist, genre: metal, source: :user, confidence: 0.3)
      create(:artist_genre, artist: artist, genre: metal, source: :lastfm, confidence: 0.6)
      track = create(:track, :with_artists, artists: [artist])
      create(:track_genre, track: track, genre: metal, source: :user, confidence: 1.0)

      described_class.new.by_track([track.id])

      expect(TrackGenre.where(track: track, genre: metal).pluck(:source, :confidence))
        .to contain_exactly(["user", 1.0], ["lastfm", 0.6])
    end

    it "refreshes an existing row's confidence on re-derivation" do
      artist = create(:artist, :with_genres, genres: [metal], genre_source: :lastfm, genre_confidence: 0.2)
      track = create(:track, :with_artists, artists: [artist])
      described_class.new.by_track([track.id])

      ArtistGenre.sole.update!(confidence: 0.85)
      described_class.new.by_track([track.id])

      expect(TrackGenre.sole.confidence).to be_within(0.001).of(0.85)
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

    it "keeps a co-artist's stronger confidence when re-derived from the weaker artist" do
      strong = create(:artist, :with_genres, genres: [metal], genre_source: :lastfm, genre_confidence: 0.9)
      weak = create(:artist, :with_genres, genres: [metal], genre_source: :lastfm, genre_confidence: 0.1)
      create(:track, :with_artists, artists: [strong, weak])

      described_class.new.by_artist([weak.id])

      expect(TrackGenre.sole.confidence).to be_within(0.001).of(0.9)
    end
  end
end
