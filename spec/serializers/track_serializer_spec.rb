# frozen_string_literal: true

require "rails_helper"

RSpec.describe TrackSerializer do
  let(:user) { create(:user) }

  # Genres arrive through Genres::Loader rather than the track_genres association, because
  # what a genre means depends on the user asking.
  def serialize(track)
    loaded = Track.with_catalog_associations.find(track.id)
    described_class.new(loaded, params: { genres: Genres::Loader.new(user).for_tracks([track]) })
                   .serializable_hash
  end

  it "serializes a track with nested album, artists, and source-attributed genres" do
    album = create(:album, title: "Reign in Blood", release_year: 1986)
    artist = create(:artist, name: "Slayer")
    genre = create(:genre, name: "thrash metal")
    track = create(:track, :with_artists, :with_genres, title: "Angel of Death", album: album,
                                                        duration_ms: 290_000, popularity: 65,
                                                        artists: [artist], genres: [genre],)

    result = serialize(track)

    expect(result).to include(
      "id" => track.id,
      "title" => "Angel of Death",
      "duration_ms" => 290_000,
      "popularity" => 65,
    )
    expect(result["album"]).to include("id" => album.id, "title" => "Reign in Blood", "release_year" => 1986)
    expect(result["artists"]).to contain_exactly(include("id" => artist.id, "name" => "Slayer"))
    expect(result["genres"]).to contain_exactly(
      { "genre_id" => genre.id, "name" => "thrash metal", "source" => "spotify", "confidence" => 1.0 },
    )
  end

  it "carries each source's confidence, so the client can rank agreement" do
    genre = create(:genre, name: "metal")
    track = create(:track)
    create(:track_genre, :from_musicbrainz, track: track, genre: genre, confidence: 0.7)
    create(:track_genre, :from_lastfm, track: track, genre: genre, confidence: 0.95)

    genres = serialize(track)["genres"]

    expect(genres.map { |entry| [entry["source"], entry["confidence"]] })
      .to contain_exactly(["musicbrainz", 0.7], ["lastfm", 0.95])
  end

  it "lists the same genre once per source, keyed by genre_id rather than a row id" do
    genre = create(:genre, name: "metal")
    track = create(:track)
    create(:track_genre, track: track, genre: genre, source: :spotify)
    create(:track_genre, track: track, genre: genre, source: :musicbrainz)

    genres = serialize(track)["genres"]

    expect(genres.pluck("source")).to contain_exactly("spotify", "musicbrainz")
    expect(genres.pluck("genre_id")).to eq([genre.id, genre.id])
    expect(genres.first).not_to have_key("id")
  end

  it "renders a genre the user added by hand, which has no catalog row at all" do
    genre = create(:genre, name: "post-metal")
    track = create(:track)
    create(:track_genre_override, :added, user: user, track: track, genre: genre)

    expect(serialize(track)["genres"]).to contain_exactly(
      { "genre_id" => genre.id, "name" => "post-metal", "source" => "user", "confidence" => 1.0 },
    )
  end

  it "omits a genre the user hid" do
    genre = create(:genre, name: "metal")
    track = create(:track)
    create(:track_genre, track: track, genre: genre)
    create(:track_genre_override, user: user, track: track, genre: genre)

    expect(serialize(track)["genres"]).to be_empty
  end
end
