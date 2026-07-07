# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::LibrarySyncInitializer do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user) }

  describe "#call" do
    context "with no playlists to sync" do
      it "returns skipped result" do
        result = service.call
        expect(result.skipped_reason).to eq("no playlists to sync")
      end

      it "does not create a session" do
        expect { service.call }.not_to change(SyncSession, :count)
      end
    end

    context "with sync-enabled, available playlists" do
      let!(:syncable_playlists) do
        create_list(:playlist, 3, user: user, sync_enabled: true, available_on_spotify: true)
      end

      it "returns success result" do
        result = service.call
        expect(result.success?).to be(true)
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
        result = service.call
        expect(result.sync_session.status).to eq("running")
      end

      it "sets session started_at" do
        result = service.call
        expect(result.sync_session.started_at).to be_within(1.second).of(Time.current)
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
        expect(result.playlist_session_ids.size).to eq(1)
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

    context "when user has playlists but none are syncable" do
      let!(:disabled_playlist) do
        create(:playlist, user: user, sync_enabled: false, available_on_spotify: true)
      end

      it "returns skipped result" do
        result = service.call
        expect(result.skipped_reason).to eq("no playlists to sync")
      end
    end
  end
end
