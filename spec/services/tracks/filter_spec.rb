# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tracks::Filter do
  let(:user) { create(:user) }
  let(:playlist) { create(:playlist, user: user) }
  let(:version) { create(:playlist_version, :current, playlist: playlist) }

  let(:metal) { create(:genre, name: "metal") }
  let(:jazz) { create(:genre, name: "jazz") }

  let(:old_album) { create(:album, title: "Debut", release_year: 2019) }
  let(:recent_album) { create(:album, title: "Sequel", release_year: 2021) }

  let(:alpha) do
    build_track("Alpha", genre: metal, artist_name: "Anthrax",
                         album: old_album, duration_ms: 100_000, popularity: 50, explicit: false,)
  end
  let(:beta) do
    build_track("Beta", genre: jazz, artist_name: "Miles Davis",
                        album: recent_album, duration_ms: 200_000, popularity: 90, explicit: true,)
  end
  let(:alphabet) do
    build_track("Alphabet", genre: metal, artist_name: "Metallica",
                            album: recent_album, duration_ms: 300_000, popularity: 10, explicit: false,)
  end

  def build_track(title, genre:, artist_name:, **track_attrs)
    create(:track, :in_library, :with_genres, :with_artists,
           current_version: version, title: title, genres: [genre],
           artists: [create(:artist, name: artist_name)], **track_attrs,)
  end

  def titles(params)
    described_class.new(user, params).call.map(&:title)
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
    it "filters by album title substring (case-insensitive)" do
      expect(titles(album: "debut")).to contain_exactly("Alpha")
    end

    it "filters by album id" do
      expect(titles(album: old_album.id)).to contain_exactly("Alpha")
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

    it "sorts by release year ascending, breaking ties by id" do
      expect(titles(sort: "year", order: "asc")).to eq(%w[Alpha Beta Alphabet])
    end

    it "sorts by release year descending" do
      expect(titles(sort: "year", order: "desc")).to eq(%w[Beta Alphabet Alpha])
    end

    it "sorts by album title ascending" do
      expect(titles(sort: "album", order: "asc")).to eq(%w[Alpha Beta Alphabet])
    end

    it "sorts by artist name ascending" do
      expect(titles(sort: "artist", order: "asc")).to eq(%w[Alpha Alphabet Beta])
    end

    it "orders tracks whose album has no release year last, regardless of direction" do
      build_track("Undated", genre: metal, artist_name: "Unknown", album: create(:album, release_year: nil))

      expect(titles(sort: "year", order: "asc").last).to eq("Undated")
      expect(titles(sort: "year", order: "desc").last).to eq("Undated")
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
