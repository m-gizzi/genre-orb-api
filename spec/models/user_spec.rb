# frozen_string_literal: true

require "rails_helper"

RSpec.describe User do
  let(:user) { create(:user) }

  def add_to_library(owner, track)
    playlist = create(:playlist, user: owner)
    version = create(:playlist_version, playlist: playlist)
    create(:playlist_version_track, playlist_version: version, track: track)
    playlist.update!(current_version: version)
    version
  end

  describe "#library_tracks" do
    it "includes tracks in the current version of the user's playlists" do
      track = create(:track)
      add_to_library(user, track)

      expect(user.library_tracks).to include(track)
    end

    it "excludes tracks that live only in a non-current version" do
      playlist = create(:playlist, user: user)
      current = create(:playlist_version, playlist: playlist)
      superseded = create(:playlist_version, playlist: playlist)
      current_track = create(:track)
      old_track = create(:track)
      create(:playlist_version_track, playlist_version: current, track: current_track)
      create(:playlist_version_track, playlist_version: superseded, track: old_track)
      playlist.update!(current_version: current)

      expect(user.library_tracks).to include(current_track)
      expect(user.library_tracks).not_to include(old_track)
    end

    it "excludes another user's tracks" do
      other_track = create(:track)
      add_to_library(create(:user), other_track)

      expect(user.library_tracks).not_to include(other_track)
    end

    it "returns a track once even when it appears in several playlists" do
      track = create(:track)
      add_to_library(user, track)
      add_to_library(user, track)

      expect(user.library_tracks.to_a.count(track)).to eq(1)
    end
  end

  describe "#library_albums" do
    it "includes albums of current-version tracks and excludes other users'" do
      album = create(:album)
      add_to_library(user, create(:track, album: album))

      other_album = create(:album)
      add_to_library(create(:user), create(:track, album: other_album))

      expect(user.library_albums).to include(album)
      expect(user.library_albums).not_to include(other_album)
    end
  end

  describe "#library_genres" do
    it "includes genres of current-version tracks and excludes other users'" do
      genre = create(:genre)
      track = create(:track)
      create(:track_genre, track: track, genre: genre)
      add_to_library(user, track)

      other_genre = create(:genre)
      other_track = create(:track)
      create(:track_genre, track: other_track, genre: other_genre)
      add_to_library(create(:user), other_track)

      expect(user.library_genres).to include(genre)
      expect(user.library_genres).not_to include(other_genre)
    end
  end

  describe "#library_artists" do
    it "includes artists of current-version tracks and excludes other users'" do
      artist = create(:artist)
      track = create(:track)
      create(:track_artist, track: track, artist: artist)
      add_to_library(user, track)

      other_artist = create(:artist)
      other_track = create(:track)
      create(:track_artist, track: other_track, artist: other_artist)
      add_to_library(create(:user), other_track)

      expect(user.library_artists).to include(artist)
      expect(user.library_artists).not_to include(other_artist)
    end
  end
end
