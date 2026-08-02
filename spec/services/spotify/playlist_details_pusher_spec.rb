# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::PlaylistDetailsPusher do
  let(:user) { create(:user) }
  let!(:connection) do
    create(:service_connection, user: user, service_user_id: "spotify_user_1",
                                access_token: "test_token", token_expires_at: 1.hour.from_now)
  end
  let(:playlist) do
    create(:playlist, :with_spotify, user: user, name: "Old Name", description: "Old description")
  end
  let(:update_url) { "#{SpotifyAdapter::BASE_URL}/playlists/#{playlist.spotify_id}" }

  def stub_update(status: 200)
    stub_request(:put, update_url).to_return(status: status, body: "")
  end

  it "pushes only the changed mirrored attributes" do
    stub = stub_request(:put, update_url)
           .with(body: { name: "New Name" }.to_json)
           .to_return(status: 200, body: "")

    described_class.new(playlist, { name: "New Name" }).call

    expect(stub).to have_been_requested
    expect(playlist.reload.name).to eq("New Name")
  end

  it "sends the description as an empty string when it is cleared" do
    stub = stub_request(:put, update_url)
           .with(body: { description: "" }.to_json)
           .to_return(status: 200, body: "")

    described_class.new(playlist, { description: nil }).call

    expect(stub).to have_been_requested
  end

  it "maps is_public onto Spotify's public key" do
    stub = stub_request(:put, update_url)
           .with(body: { public: true }.to_json)
           .to_return(status: 200, body: "")

    described_class.new(playlist, { is_public: true }).call

    expect(stub).to have_been_requested
  end

  it "does not call Spotify when only local attributes change" do
    stub = stub_update

    described_class.new(playlist, { sync_enabled: true }).call

    expect(stub).not_to have_been_requested
    expect(playlist.reload.sync_enabled).to be(true)
  end

  it "does not call Spotify when nothing changed" do
    stub = stub_update

    described_class.new(playlist, { name: "Old Name" }).call

    expect(stub).not_to have_been_requested
  end

  it "leaves the local record untouched when Spotify rejects the update" do
    stub_update(status: 502)

    expect { described_class.new(playlist, { name: "New Name" }).call }
      .to raise_error(SpotifyAdapter::ApiError)

    expect(playlist.reload.name).to eq("Old Name")
  end

  it "leaves the local record untouched when rate limited" do
    stub_request(:put, update_url).to_return(status: 429, headers: { "Retry-After" => "12" })

    expect { described_class.new(playlist, { name: "New Name" }).call }
      .to raise_error(SpotifyAdapter::RateLimitError)

    expect(playlist.reload.name).to eq("Old Name")
  end

  it "does not call Spotify when the new attributes are invalid" do
    stub = stub_update

    expect { described_class.new(playlist, { name: "" }).call }
      .to raise_error(ActiveRecord::RecordInvalid)

    expect(stub).not_to have_been_requested
    expect(playlist.reload.name).to eq("Old Name")
  end

  it "skips the push for a playlist that is not on Spotify" do
    liked = create(:liked_songs_playlist, user: user)
    stub = stub_request(:put, %r{/playlists/}).to_return(status: 200, body: "")

    described_class.new(liked, { name: "Renamed" }).call

    expect(stub).not_to have_been_requested
  end
end
