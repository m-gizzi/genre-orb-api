# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::Creator do
  let(:user) { create(:user) }
  let(:source) { create(:playlist, :with_spotify, user: user) }
  let(:create_url) { "#{SpotifyAdapter::BASE_URL}/users/spotify_user_1/playlists" }

  before do
    create(:service_connection, user: user, service_user_id: "spotify_user_1",
                                access_token: "test_token", token_expires_at: 1.hour.from_now,)
  end

  def stub_create(status: 201, body: { "id" => "spotify_new_1" })
    stub_request(:post, create_url)
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "converting an existing playlist" do
    let(:target) { create(:playlist, :with_spotify, user: user) }

    it "creates a draft smart playlist against the existing target" do
      smart_playlist = described_class.new(
        user, { target_playlist_id: target.id, source_playlist_ids: [source.id] },
      ).call

      expect(smart_playlist.target_playlist).to eq(target)
      expect(smart_playlist.source_playlists).to contain_exactly(source)
      expect(smart_playlist.rules).to eq(SmartPlaylist::EMPTY_RULES)
      expect(smart_playlist.is_enabled).to be(false)
    end

    it "forces the target playlist to sync" do
      target.update!(sync_enabled: false)

      described_class.new(user, { target_playlist_id: target.id, source_playlist_ids: [source.id] }).call

      expect(target.reload.sync_enabled).to be(true)
    end

    it "never calls Spotify" do
      stub = stub_create

      described_class.new(user, { target_playlist_id: target.id, source_playlist_ids: [source.id] }).call

      expect(stub).not_to have_been_requested
    end

    it "rejects a target that already has a smart playlist" do
      create(:smart_playlist, target_playlist: target)

      expect do
        described_class.new(user, { target_playlist_id: target.id, source_playlist_ids: [source.id] }).call
      end.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "does not find another user's playlist" do
      other = create(:playlist, :with_spotify)

      expect do
        described_class.new(user, { target_playlist_id: other.id, source_playlist_ids: [source.id] }).call
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "ignores source ids belonging to another user" do
      other = create(:playlist, :with_spotify)

      expect do
        described_class.new(user, { target_playlist_id: target.id, source_playlist_ids: [other.id] }).call
      end.to raise_error(ActiveRecord::RecordInvalid, /source playlists/i)
    end
  end

  describe "creating a new playlist and smart playlist together" do
    let(:params) do
      {
        target_playlist_attributes: { name: "Metal Mix", description: "Heavy", is_public: false },
        source_playlist_ids: [source.id],
      }
    end

    it "creates the playlist on Spotify and points the smart playlist at it" do
      stub_create

      smart_playlist = described_class.new(user, params).call

      expect(smart_playlist.target_playlist.spotify_id).to eq("spotify_new_1")
      expect(smart_playlist.target_playlist.name).to eq("Metal Mix")
      expect(smart_playlist.source_playlists).to contain_exactly(source)
    end

    it "does not create a Spotify playlist when no sources were given" do
      stub = stub_create

      expect { described_class.new(user, params.merge(source_playlist_ids: [])).call }
        .to raise_error(ActiveRecord::RecordInvalid, /source playlists/i)

      expect(stub).not_to have_been_requested
      expect(Playlist.where(name: "Metal Mix")).to be_empty
    end

    it "creates nothing locally when Spotify rejects the playlist" do
      stub_create(status: 500, body: { "error" => "boom" })

      expect { described_class.new(user, params).call }.to raise_error(SpotifyAdapter::ApiError)

      expect(SmartPlaylist.count).to eq(0)
      expect(Playlist.where(name: "Metal Mix")).to be_empty
    end
  end

  it "raises when neither a target nor new playlist attributes are given" do
    expect { described_class.new(user, { source_playlist_ids: [source.id] }).call }
      .to raise_error(described_class::MissingTargetError)
  end
end
