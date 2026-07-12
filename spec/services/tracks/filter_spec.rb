# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracks::Filter do
  let(:user) { create(:user) }
  let(:playlist) { create(:playlist, user: user) }
  let(:version) do
    create(:playlist_version, playlist: playlist).tap { |v| playlist.update!(current_version: v) }
  end

  let(:metal) { create(:genre, name: "metal") }
  let(:jazz) { create(:genre, name: "jazz") }

  let(:album_2019) { create(:album, release_year: 2019) }
  let(:album_2021) { create(:album, release_year: 2021) }

  let(:alpha) do
    build_track("Alpha", album: album_2019, duration_ms: 100_000, popularity: 50, explicit: false,
                         genre: metal, artist_name: "Anthrax")
  end
  let(:beta) do
    build_track("Beta", album: album_2021, duration_ms: 200_000, popularity: 90, explicit: true,
                        genre: jazz, artist_name: "Miles Davis")
  end
  let(:alphabet) do
    build_track("Alphabet", album: album_2021, duration_ms: 300_000, popularity: 10, explicit: false,
                            genre: metal, artist_name: "Metallica")
  end

  def build_track(title, album:, duration_ms:, popularity:, explicit:, genre:, artist_name:)
    track = create(:track, title: title, album: album, duration_ms: duration_ms,
                           popularity: popularity, explicit: explicit)
    create(:track_genre, track: track, genre: genre)
    create(:track_artist, track: track, artist: create(:artist, name: artist_name))
    create(:playlist_version_track, playlist_version: version, track: track)
    track
  end

  def titles(params)
    described_class.new(user.library_tracks, params).call.map(&:title)
  end

  before { [alpha, beta, alphabet] }

  describe "no filters" do
    it "returns all library tracks sorted by title asc by default" do
      expect(titles({})).to eq(%w[Alpha Alphabet Beta])
    end
  end

  describe "genre filter" do
    it "filters by genre name (normalized)" do
      expect(titles(genre: "Metal")).to contain_exactly("Alpha", "Alphabet")
    end

    it "filters by genre id" do
      expect(titles(genre: jazz.id)).to contain_exactly("Beta")
    end
  end

  describe "artist filter" do
    it "filters by artist name substring (case-insensitive)" do
      expect(titles(artist: "anthrax")).to contain_exactly("Alpha")
    end

    it "filters by artist id" do
      artist = alphabet.artists.first
      expect(titles(artist: artist.id)).to contain_exactly("Alphabet")
    end
  end

  describe "album filter" do
    it "filters by album_id" do
      expect(titles(album_id: album_2019.id)).to contain_exactly("Alpha")
    end
  end

  describe "year filter" do
    it "filters by exact year" do
      expect(titles(year: 2019)).to contain_exactly("Alpha")
    end

    it "filters by year range" do
      expect(titles(year_min: 2020)).to contain_exactly("Beta", "Alphabet")
      expect(titles(year_max: 2020)).to contain_exactly("Alpha")
    end
  end

  describe "duration filter" do
    it "filters by duration range (ms)" do
      expect(titles(duration_min: 150_000)).to contain_exactly("Beta", "Alphabet")
      expect(titles(duration_max: 150_000)).to contain_exactly("Alpha")
    end
  end

  describe "title filter" do
    it "matches a case-insensitive substring" do
      expect(titles(title: "alph")).to contain_exactly("Alpha", "Alphabet")
    end
  end

  describe "explicit filter" do
    it "filters explicit tracks" do
      expect(titles(explicit: true)).to contain_exactly("Beta")
      expect(titles(explicit: false)).to contain_exactly("Alpha", "Alphabet")
    end
  end

  describe "sorting" do
    it "sorts by popularity descending" do
      expect(titles(sort: "popularity", order: "desc")).to eq(%w[Beta Alpha Alphabet])
    end

    it "sorts by duration ascending" do
      expect(titles(sort: "duration", order: "asc")).to eq(%w[Alpha Beta Alphabet])
    end

    it "ignores an unknown sort key and falls back to title" do
      expect(titles(sort: "bogus")).to eq(%w[Alpha Alphabet Beta])
    end
  end

  describe "combined filters" do
    it "applies genre + duration together" do
      expect(titles(genre: "metal", duration_min: 250_000)).to contain_exactly("Alphabet")
    end
  end
end
