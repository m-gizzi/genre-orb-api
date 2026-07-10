# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::LibrarySyncInitializer do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  describe "#call" do
    context "when Spotify is not connected" do
      before { create(:playlist, user: user, sync_enabled: true, available_on_spotify: true) }

      it "returns a spotify_not_connected outcome" do
        expect(service.call.outcome).to eq(:spotify_not_connected)
      end

      it "does not create a session" do
        expect { service.call }.not_to change(SyncSession, :count)
      end
    end

    context "when Spotify is connected" do
      before { create(:service_connection, user: user) }

      context "with no playlists to sync" do
        it "returns a no_playlists outcome" do
          expect(service.call.outcome).to eq(:no_playlists)
        end

        it "does not create a session" do
          expect { service.call }.not_to change(SyncSession, :count)
        end
      end

      context "when user has playlists but none are syncable" do
        before { create(:playlist, user: user, sync_enabled: false, available_on_spotify: true) }

        it "returns a no_playlists outcome" do
          expect(service.call.outcome).to eq(:no_playlists)
        end
      end

      context "when a sync is already in progress" do
        before do
          create(:playlist, user: user, sync_enabled: true, available_on_spotify: true)
          create(:sync_session, :running, user: user)
        end

        it "returns an already_in_progress outcome" do
          expect(service.call.outcome).to eq(:already_in_progress)
        end

        it "does not create another session" do
          expect { service.call }.not_to change(SyncSession, :count)
        end
      end

      context "with sync-enabled, available playlists" do
        before do
          create_list(:playlist, 3, user: user, sync_enabled: true, available_on_spotify: true)
        end

        it "returns a started outcome" do
          expect(service.call).to be_started
        end

        it "creates a sync session" do
          expect { service.call }.to change(SyncSession, :count).by(1)
        end

        it "returns the created session" do
          result = service.call
          expect(result.sync_session).to be_a(SyncSession)
          expect(result.sync_session.user).to eq(user)
        end

        it "sets session to running" do
          expect(service.call.sync_session.status).to eq("running")
        end

        it "sets session started_at" do
          expect(service.call.sync_session.started_at).to be_within(1.second).of(Time.current)
        end

        it "creates sync session playlists" do
          expect { service.call }.to change(SyncSessionPlaylist, :count).by(3)
        end

        it "returns playlist session ids" do
          result = service.call
          expect(result.playlist_session_ids.size).to eq(3)
          expect(result.playlist_session_ids).to all(be_a(Integer))
        end

        it "links playlist sessions to sync session" do
          result = service.call
          playlist_sessions = SyncSessionPlaylist.where(id: result.playlist_session_ids)
          expect(playlist_sessions.map(&:sync_session_id).uniq).to eq([result.sync_session.id])
        end

        it "enqueues a setup job for each playlist" do
          expect { service.call }.to have_enqueued_job(PlaylistSyncSetupJob).exactly(3).times
        end
      end

      context "with mixed playlist statuses" do
        let!(:syncable_playlist) do
          create(:playlist, user: user, sync_enabled: true, available_on_spotify: true)
        end
        let!(:disabled_playlist) do
          create(:playlist, user: user, sync_enabled: false, available_on_spotify: true)
        end
        let!(:unavailable_playlist) do
          create(:playlist, user: user, sync_enabled: true, available_on_spotify: false)
        end

        it "only includes sync-enabled and available playlists" do
          result = service.call
          playlist_ids = SyncSessionPlaylist.where(id: result.playlist_session_ids).pluck(:playlist_id)
          expect(playlist_ids).to eq([syncable_playlist.id])
        end

        it "excludes disabled playlists" do
          result = service.call
          playlist_ids = SyncSessionPlaylist.where(id: result.playlist_session_ids).pluck(:playlist_id)
          expect(playlist_ids).not_to include(disabled_playlist.id)
        end

        it "excludes unavailable playlists" do
          result = service.call
          playlist_ids = SyncSessionPlaylist.where(id: result.playlist_session_ids).pluck(:playlist_id)
          expect(playlist_ids).not_to include(unavailable_playlist.id)
        end
      end
    end
  end
end
