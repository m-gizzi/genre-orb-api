# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1 genre curation" do
  let(:user) { create(:user) }
  let(:playlist) { create(:playlist, user: user) }
  let(:version) { create(:playlist_version, :current, playlist: playlist) }
  let(:metal) { create(:genre, name: "metal") }

  def genre_names = response.parsed_body["data"].pluck("name")

  describe "POST /api/v1/tracks/:track_id/genres" do
    let(:track) { create(:track, :in_library, current_version: version) }

    it "returns 401 when not authenticated" do
      post "/api/v1/tracks/#{track.id}/genres", params: { genre: { genre_id: metal.id, action: "added" } }

      expect(response).to have_http_status(:unauthorized)
    end

    context "when authenticated" do
      before { sign_in user }

      it "adds a genre and returns the track's effective genres" do
        post "/api/v1/tracks/#{track.id}/genres", params: { genre: { genre_id: metal.id, action: "added" } }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["data"])
          .to contain_exactly(hash_including("genre_id" => metal.id, "name" => "metal", "source" => "user"))
      end

      it "creates a genre named for the first time, so a missing vocabulary can be typed in" do
        post "/api/v1/tracks/#{track.id}/genres", params: { genre: { name: "  Post   Metal ", action: "added" } }

        expect(genre_names).to contain_exactly("post metal")
        expect(Genre.find_by(name: "post metal")).to be_present
      end

      it "hides a provider's genre" do
        create(:track_genre, track: track, genre: metal)

        post "/api/v1/tracks/#{track.id}/genres", params: { genre: { genre_id: metal.id, action: "hidden" } }

        expect(response.parsed_body["data"]).to be_empty
      end

      it "upserts rather than duplicating, so changing your mind is the same call" do
        create(:track_genre_override, user: user, track: track, genre: metal)

        post "/api/v1/tracks/#{track.id}/genres", params: { genre: { genre_id: metal.id, action: "added" } }

        expect(TrackGenreOverride.where(user: user, track: track, genre: metal).count).to eq(1)
        expect(genre_names).to contain_exactly("metal")
      end

      it "rejects an action that is neither hidden nor added" do
        post "/api/v1/tracks/#{track.id}/genres", params: { genre: { genre_id: metal.id, action: "burninate" } }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "rejects a request naming no genre at all" do
        post "/api/v1/tracks/#{track.id}/genres", params: { genre: { action: "added" } }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "404s for a track outside the user's library" do
        post "/api/v1/tracks/#{create(:track).id}/genres",
             params: { genre: { genre_id: metal.id, action: "added" } }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "DELETE /api/v1/tracks/:track_id/genres/:id" do
    let(:track) { create(:track, :in_library, current_version: version) }

    before { sign_in user }

    it "reverts to what the providers say" do
      create(:track_genre, track: track, genre: metal)
      create(:track_genre_override, user: user, track: track, genre: metal)

      delete "/api/v1/tracks/#{track.id}/genres/#{metal.id}"

      expect(genre_names).to contain_exactly("metal")
      expect(TrackGenreOverride.count).to be_zero
    end

    it "is a no-op when there was no override" do
      delete "/api/v1/tracks/#{track.id}/genres/#{metal.id}"

      expect(response).to have_http_status(:ok)
    end
  end

  describe "artist genres" do
    let(:artist) { create(:artist) }
    let!(:track) { create(:track, :in_library, :with_artists, current_version: version, artists: [artist]) }

    before { sign_in user }

    it "adds a genre and returns the artist's effective genres" do
      post "/api/v1/artists/#{artist.id}/genres", params: { genre: { genre_id: metal.id, action: "added" } }

      expect(response.parsed_body["data"])
        .to contain_exactly(hash_including("name" => "metal", "source" => "user"))
    end

    it "hides a provider's genre on the artist" do
      create(:artist_genre, artist: artist, genre: metal)

      post "/api/v1/artists/#{artist.id}/genres", params: { genre: { genre_id: metal.id, action: "hidden" } }

      expect(response.parsed_body["data"]).to be_empty
    end

    it "404s for an artist outside the user's library" do
      post "/api/v1/artists/#{create(:artist).id}/genres",
           params: { genre: { genre_id: metal.id, action: "added" } }

      expect(response).to have_http_status(:not_found)
    end

    # The projection itself is Genres::EffectiveScope's; what matters here is that the
    # track endpoint reads it, so an artist-level edit shows up on the track view.
    it "projects an artist-level add onto the artist's tracks" do
      create(:artist_genre_override, :added, user: user, artist: artist, genre: metal)

      get "/api/v1/tracks/#{track.id}"

      expect(response.parsed_body["data"]["genres"].pluck("name")).to contain_exactly("metal")
    end

    it "clears an artist-hidden genre from the artist's tracks" do
      create(:artist_genre, artist: artist, genre: metal)
      create(:track_genre, track: track, genre: metal)
      create(:artist_genre_override, user: user, artist: artist, genre: metal)

      get "/api/v1/tracks/#{track.id}"

      expect(response.parsed_body["data"]["genres"]).to be_empty
    end
  end

  describe "GET/PATCH /api/v1/genre_preferences" do
    before { sign_in user }

    it "reports neutral defaults for a user who has curated nothing" do
      get "/api/v1/genre_preferences"

      expect(response.parsed_body["data"]["sources"]).to eq(
        "spotify" => { "enabled" => true, "min_confidence" => 0.0 },
        "musicbrainz" => { "enabled" => true, "min_confidence" => 0.0 },
        "lastfm" => { "enabled" => true, "min_confidence" => 0.0 },
      )
      expect(response.parsed_body["data"]["blocked_genres"]).to be_empty
    end

    it "merges a partial source update rather than replacing the whole hash" do
      user.update!(genre_source_preferences: { "spotify" => { "enabled" => false } })

      patch "/api/v1/genre_preferences",
            params: { genre_preferences: { sources: { lastfm: { min_confidence: 0.3 } } } }

      sources = response.parsed_body["data"]["sources"]
      expect(sources["spotify"]["enabled"]).to be(false)
      expect(sources["lastfm"]["min_confidence"]).to eq(0.3)
    end

    it "replaces the blocklist wholesale and returns it with names" do
      rock = create(:genre, name: "rock")
      create(:blocked_genre, user: user, genre: rock)

      patch "/api/v1/genre_preferences", params: { genre_preferences: { blocked_genre_ids: [metal.id] } }

      expect(response.parsed_body["data"]["blocked_genres"])
        .to contain_exactly({ "id" => metal.id, "name" => "metal" })
    end

    it "rejects a source nobody can configure" do
      patch "/api/v1/genre_preferences",
            params: { genre_preferences: { sources: { user: { enabled: false } } } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects a confidence floor outside 0..1" do
      patch "/api/v1/genre_preferences",
            params: { genre_preferences: { sources: { lastfm: { min_confidence: 4 } } } }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "the blocklist's reach" do
    before do
      sign_in user
      create(:track, :in_library, :with_genres, current_version: version, genres: [metal])
      create(:blocked_genre, user: user, genre: metal)
    end

    it "hides the genre from the list" do
      get "/api/v1/genres"

      expect(genre_names).to be_empty
    end

    it "shows it again under include_blocked, flagged, so it can be unblocked" do
      get "/api/v1/genres", params: { include_blocked: true }

      expect(response.parsed_body["data"])
        .to contain_exactly(hash_including("name" => "metal", "blocked" => true))
    end

    it "keeps the detail page reachable, which is the other place you unblock it" do
      get "/api/v1/genres/#{metal.id}"

      expect(response.parsed_body["data"]).to include("name" => "metal", "blocked" => true)
    end

    it "stops the ?genre= filter matching it" do
      get "/api/v1/tracks", params: { genre: metal.id }

      expect(response.parsed_body["data"]).to be_empty
    end
  end
end
