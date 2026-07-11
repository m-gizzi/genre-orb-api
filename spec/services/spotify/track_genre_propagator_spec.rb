# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::TrackGenrePropagator do
  let(:service) { described_class.new }
  let(:track) { create(:track) }

  describe "#call" do
    it "creates genres and track-genre joins" do
      service.call([{ track_id: track.id, genre_name: "Death Metal" }])

      expect(Genre.pluck(:name)).to contain_exactly("death metal")
      expect(track.reload.genres.pluck(:name)).to contain_exactly("death metal")
    end

    it "writes spotify-sourced joins with full confidence" do
      service.call([{ track_id: track.id, genre_name: "rock" }])

      track_genre = TrackGenre.find_by(track: track)
      expect(track_genre.source).to eq("spotify")
      expect(track_genre.confidence).to eq(1.0)
    end

    it "is idempotent across runs" do
      pairs = [{ track_id: track.id, genre_name: "rock" }]
      service.call(pairs)

      expect { service.call(pairs) }.not_to change(TrackGenre, :count)
    end

    it "normalizes names and dedupes within a run" do
      service.call([
                     { track_id: track.id, genre_name: "Death Metal" },
                     { track_id: track.id, genre_name: "death metal" },
                     { track_id: track.id, genre_name: "  DEATH   METAL " },
                   ])

      expect(track.reload.genres.pluck(:name)).to contain_exactly("death metal")
      expect(TrackGenre.where(track: track).count).to eq(1)
    end

    it "skips blank genre names" do
      service.call([{ track_id: track.id, genre_name: "  " }])

      expect(Genre.count).to eq(0)
      expect(TrackGenre.count).to eq(0)
    end

    it "does not clobber an existing user-sourced genre for the same track/genre" do
      genre = create(:genre, name: "rock")
      create(:track_genre, :user_override, track: track, genre: genre)

      service.call([{ track_id: track.id, genre_name: "rock" }])

      sources = TrackGenre.where(track: track, genre: genre).pluck(:source)
      expect(sources).to contain_exactly("user", "spotify")
    end

    context "with empty input" do
      it "is a no-op" do
        expect { service.call([]) }.not_to change(TrackGenre, :count)
      end
    end
  end
end
