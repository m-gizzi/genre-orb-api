# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::ArtistMetadataSyncInitializer do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user, sync_all: sync_all) }
  let(:sync_all) { false }

  let(:library_track) do
    playlist = create(:playlist, user: user)
    version = create(:playlist_version, playlist: playlist)
    playlist.update!(current_version: version)
    track = create(:track)
    create(:playlist_version_track, playlist_version: version, track: track)
    track
  end

  def add_library_artist(**attrs)
    artist = create(:artist, **attrs)
    create(:track_artist, track: library_track, artist: artist)
    artist
  end

  describe "#call" do
    context "with no artists to sync" do
      it "returns skipped result" do
        result = service.call
        expect(result.skipped_reason).to eq("no artists to sync")
      end

      it "does not create a session" do
        expect { service.call }.not_to change(ArtistMetadataSession, :count)
      end
    end

    context "when unfetched artists belong to another user's library" do
      before do
        version = create(:playlist_version, playlist: create(:playlist, user: create(:user)))
        track = create(:track)
        create(:playlist_version_track, playlist_version: version, track: track)
        create(:track_artist, track: track, artist: create(:artist, metadata_fetched_at: nil))
      end

      it "returns skipped result" do
        result = service.call
        expect(result.skipped_reason).to eq("no artists to sync")
      end
    end

    context "with artists that need metadata" do
      let!(:unfetched_artists) { Array.new(3) { add_library_artist(metadata_fetched_at: nil) } }
      let!(:fetched_artist) { add_library_artist(metadata_fetched_at: 1.day.ago) }

      it "creates an artist metadata session" do
        expect { service.call }.to change(ArtistMetadataSession, :count).by(1)
      end

      it "returns the created session" do
        result = service.call
        expect(result.session).to be_a(ArtistMetadataSession)
        expect(result.session.user).to eq(user)
      end

      it "sets session to running" do
        result = service.call
        expect(result.session.status).to eq("running")
      end

      it "sets correct total_batches" do
        result = service.call
        expect(result.session.total_batches).to eq(1)
      end

      it "returns batches with only unfetched artist ids" do
        result = service.call
        expect(result.batches.flatten).to match_array(unfetched_artists.map(&:id))
      end

      it "does not include already fetched artists" do
        result = service.call
        expect(result.batches.flatten).not_to include(fetched_artist.id)
      end
    end

    context "with sync_all: true" do
      let(:sync_all) { true }
      let!(:unfetched_artists) { Array.new(2) { add_library_artist(metadata_fetched_at: nil) } }
      let!(:fetched_artists) { Array.new(2) { add_library_artist(metadata_fetched_at: 1.day.ago) } }

      it "includes all artists regardless of metadata_fetched_at" do
        result = service.call
        all_ids = (unfetched_artists + fetched_artists).map(&:id)
        expect(result.batches.flatten).to match_array(all_ids)
      end
    end

    context "with more artists than batch size" do
      before do
        # More than the 50-artist batch limit.
        120.times { add_library_artist(metadata_fetched_at: nil) }
      end

      it "splits into multiple batches" do
        result = service.call
        expect(result.batches.size).to eq(3) # 50 + 50 + 20
      end

      it "sets correct total_batches on session" do
        result = service.call
        expect(result.session.total_batches).to eq(3)
      end

      it "has correct batch sizes" do
        result = service.call
        expect(result.batches[0].size).to eq(50)
        expect(result.batches[1].size).to eq(50)
        expect(result.batches[2].size).to eq(20)
      end
    end

    context "with exactly batch size artists" do
      before do
        50.times { add_library_artist(metadata_fetched_at: nil) }
      end

      it "creates single batch" do
        result = service.call
        expect(result.batches.size).to eq(1)
      end
    end
  end
end
