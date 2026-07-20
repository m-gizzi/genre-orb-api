# frozen_string_literal: true

require "rails_helper"

RSpec.describe TrackSerializer do
  it "serializes a track with nested album, artists, and source-attributed genres" do
    album = create(:album, title: "Reign in Blood", release_year: 1986)
    artist = create(:artist, name: "Slayer")
    genre = create(:genre, name: "thrash metal")
    track = create(:track, :with_artists, :with_genres, title: "Angel of Death", album: album,
                                                        duration_ms: 290_000, popularity: 65,
                                                        artists: [artist], genres: [genre],)

    loaded = Track.with_catalog_associations.find(track.id)
    result = described_class.new(loaded).serializable_hash

    expect(result).to include(
      "id" => track.id,
      "title" => "Angel of Death",
      "duration_ms" => 290_000,
      "popularity" => 65,
    )
    expect(result["album"]).to include("id" => album.id, "title" => "Reign in Blood", "release_year" => 1986)
    expect(result["artists"]).to contain_exactly(include("id" => artist.id, "name" => "Slayer"))
    track_genre = track.track_genres.first
    expect(result["genres"]).to contain_exactly(
      { "id" => track_genre.id, "genre_id" => genre.id, "name" => "thrash metal", "source" => "spotify" },
    )
  end

  it "lists the same genre once per source with distinct entry ids" do
    genre = create(:genre, name: "metal")
    track = create(:track)
    create(:track_genre, track: track, genre: genre, source: :spotify)
    create(:track_genre, track: track, genre: genre, source: :user)

    loaded = Track.with_catalog_associations.find(track.id)
    genres = described_class.new(loaded).serializable_hash["genres"]

    expect(genres.pluck("source")).to contain_exactly("spotify", "user")
    expect(genres.pluck("genre_id")).to eq([genre.id, genre.id])
    expect(genres.pluck("id").uniq.size).to eq(2)
  end
end
