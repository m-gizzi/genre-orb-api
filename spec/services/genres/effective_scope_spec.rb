# frozen_string_literal: true

require "rails_helper"

RSpec.describe Genres::EffectiveScope do
  subject(:scope) { described_class.new(user) }

  let(:user) { create(:user) }
  let(:metal) { create(:genre, name: "metal") }
  let(:seen_live) { create(:genre, name: "seen live") }

  def track_genre_names
    scope.tracks.joins(:genre).pluck("genres.name")
  end

  def artist_genre_names
    scope.artists.joins(:genre).pluck("genres.name")
  end

  describe "with no curation" do
    it "hands back the untouched relation rather than a filtered one" do
      expect(scope.tracks.to_sql).to eq(TrackGenre.all.to_sql)
      expect(scope.artists.to_sql).to eq(ArtistGenre.all.to_sql)
    end

    it "reports itself neutral at both levels" do
      expect(scope).to be_tracks_neutral
      expect(scope).to be_artists_neutral
    end

    it "returns every claim" do
      track = create(:track)
      create(:track_genre, track: track, genre: metal)
      create(:track_genre, track: track, genre: seen_live, source: :lastfm)

      expect(track_genre_names).to contain_exactly("metal", "seen live")
    end
  end

  describe "layer 1 — source toggles" do
    before { user.update!(genre_source_preferences: { lastfm: { enabled: false } }) }

    it "drops rows from a disabled source" do
      track = create(:track)
      create(:track_genre, track: track, genre: metal)
      create(:track_genre, track: track, genre: seen_live, source: :lastfm)

      expect(track_genre_names).to contain_exactly("metal")
    end

    it "applies to artist genres too" do
      artist = create(:artist)
      create(:artist_genre, artist: artist, genre: metal)
      create(:artist_genre, artist: artist, genre: seen_live, source: :lastfm)

      expect(artist_genre_names).to contain_exactly("metal")
    end

    it "is no longer neutral" do
      expect(scope).not_to be_tracks_neutral
    end
  end

  describe "layer 2 — confidence floor" do
    before { user.update!(genre_source_preferences: { lastfm: { min_confidence: 0.3 } }) }

    it "drops rows below that source's floor" do
      track = create(:track)
      create(:track_genre, track: track, genre: metal, source: :lastfm, confidence: 0.8)
      create(:track_genre, track: track, genre: seen_live, source: :lastfm, confidence: 0.1)

      expect(track_genre_names).to contain_exactly("metal")
    end

    it "leaves other sources at their own floor" do
      track = create(:track)
      create(:track_genre, track: track, genre: seen_live, source: :spotify, confidence: 0.1)

      expect(track_genre_names).to contain_exactly("seen live")
    end
  end

  describe "layer 3 — blocklist" do
    before { create(:blocked_genre, user: user, genre: seen_live) }

    it "drops the genre everywhere, whatever claimed it" do
      track = create(:track)
      create(:track_genre, track: track, genre: metal)
      create(:track_genre, track: track, genre: seen_live)
      create(:track_genre, track: track, genre: seen_live, source: :lastfm)

      expect(track_genre_names).to contain_exactly("metal")
    end

    it "drops it from artist genres too" do
      artist = create(:artist)
      create(:artist_genre, artist: artist, genre: seen_live)

      expect(artist_genre_names).to be_empty
    end
  end

  describe "layer 4 — artist overlay" do
    let(:gojira) { create(:artist) }

    it "hiding a genre removes every source's claim of it on that artist" do
      create(:artist_genre, artist: gojira, genre: metal, source: :spotify)
      create(:artist_genre, artist: gojira, genre: metal, source: :lastfm)
      create(:artist_genre_override, user: user, artist: gojira, genre: metal)

      expect(artist_genre_names).to be_empty
    end

    it "adding a genre attributes it to the user" do
      create(:artist_genre_override, :added, user: user, artist: gojira, genre: metal)

      expect(scope.artists.pluck(:source, :confidence)).to eq([["user", 1.0]])
    end

    it "projects an added genre onto the artist's tracks" do
      track = create(:track, :with_artists, artists: [gojira])
      create(:artist_genre_override, :added, user: user, artist: gojira, genre: metal)

      expect(track_genre_names).to contain_exactly("metal")
      expect(scope.tracks.pluck(:track_id)).to contain_exactly(track.id)
    end

    it "credits an added genre once to a track credited to two carrying artists" do
      other = create(:artist)
      create(:track, :with_artists, artists: [gojira, other])
      create(:artist_genre_override, :added, user: user, artist: gojira, genre: metal)
      create(:artist_genre_override, :added, user: user, artist: other, genre: metal)

      expect(track_genre_names).to contain_exactly("metal")
    end

    describe "hiding on a track with several artists" do
      let(:pop_act) { create(:artist) }
      let(:collaboration) { create(:track, :with_artists, artists: [gojira, pop_act]) }

      before do
        create(:artist_genre, artist: gojira, genre: metal)
        create(:track_genre, track: collaboration, genre: metal)
        create(:artist_genre_override, user: user, artist: gojira, genre: metal)
      end

      it "removes the genre when no other credited artist claims it" do
        expect(track_genre_names).to be_empty
      end

      it "keeps the genre when another credited artist still claims it" do
        create(:artist_genre, artist: pop_act, genre: metal)

        expect(track_genre_names).to contain_exactly("metal")
      end

      it "matches on source, so a co-artist's different source does not rescue it" do
        create(:artist_genre, artist: pop_act, genre: metal, source: :lastfm)

        expect(track_genre_names).to be_empty
      end
    end
  end

  describe "layer 5 — track overlay" do
    let(:track) { create(:track) }

    it "hiding a genre removes it from that track only" do
      other = create(:track)
      create(:track_genre, track: track, genre: metal)
      create(:track_genre, track: other, genre: metal)
      create(:track_genre_override, user: user, track: track, genre: metal)

      expect(scope.tracks.pluck(:track_id)).to contain_exactly(other.id)
    end

    it "adding a genre attributes it to the user with a null id" do
      create(:track_genre_override, :added, user: user, track: track, genre: metal)

      expect(scope.tracks.pluck(:id, :source, :confidence)).to eq([[nil, "user", 1.0]])
    end

    it "keeps the providers' claims alongside a hand-added one" do
      create(:track_genre, track: track, genre: metal, source: :lastfm)
      create(:track_genre_override, :added, user: user, track: track, genre: metal)

      expect(scope.tracks.pluck(:source)).to contain_exactly("lastfm", "user")
    end
  end

  describe "precedence — each layer undoes the one before it" do
    let(:gojira) { create(:artist) }
    let(:track) { create(:track, :with_artists, artists: [gojira]) }

    before { track }

    it "a track add resurrects a blocklisted genre on that track" do
      create(:blocked_genre, user: user, genre: seen_live)
      create(:track_genre_override, :added, user: user, track: track, genre: seen_live)

      expect(track_genre_names).to contain_exactly("seen live")
    end

    it "an artist add beats the blocklist for that artist's tracks" do
      create(:blocked_genre, user: user, genre: seen_live)
      create(:artist_genre_override, :added, user: user, artist: gojira, genre: seen_live)

      expect(track_genre_names).to contain_exactly("seen live")
    end

    it "a track hide beats an artist add" do
      create(:artist_genre_override, :added, user: user, artist: gojira, genre: metal)
      create(:track_genre_override, user: user, track: track, genre: metal)

      expect(track_genre_names).to be_empty
    end

    it "a track add undoes an artist hide, re-attributing the genre to the user" do
      create(:artist_genre, artist: gojira, genre: metal)
      create(:track_genre, track: track, genre: metal)
      create(:artist_genre_override, user: user, artist: gojira, genre: metal)
      create(:track_genre_override, :added, user: user, track: track, genre: metal)

      expect(scope.tracks.pluck(:source)).to contain_exactly("user")
    end

    it "a source toggle cannot touch a hand-added genre" do
      user.update!(genre_source_preferences: { lastfm: { enabled: false } })
      create(:track_genre_override, :added, user: user, track: track, genre: metal)

      expect(track_genre_names).to contain_exactly("metal")
    end
  end

  describe "isolation between users" do
    it "leaves another user's genres alone" do
      track = create(:track)
      create(:track_genre, track: track, genre: metal)
      create(:track_genre_override, user: user, track: track, genre: metal)

      expect(track_genre_names).to be_empty
      expect(described_class.new(create(:user)).tracks.joins(:genre).pluck("genres.name"))
        .to contain_exactly("metal")
    end
  end
end
