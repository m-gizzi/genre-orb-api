# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::PlaylistCreator do
  let(:user) { create(:user) }
  let(:create_url) { "#{Spotify::Client::BASE_URL}/users/spotify_user_1/playlists" }
  let(:attributes) { { name: "Metal Mix", description: "Heavy stuff" } }

  before do
    create(:service_connection, user: user, service_user_id: "spotify_user_1",
                                access_token: "test_token", token_expires_at: 1.hour.from_now,)
  end

  def stub_create(status: 201, body: { "id" => "spotify_new_1" })
    stub_request(:post, create_url)
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "creates the playlist on Spotify and stores the returned id" do
    stub_create

    playlist = described_class.new(user, attributes).call

    expect(playlist).to be_persisted
    expect(playlist.spotify_id).to eq("spotify_new_1")
    expect(playlist.name).to eq("Metal Mix")
    expect(playlist.description).to eq("Heavy stuff")
  end

  it "does not send Spotify's public key, leaving its default in place" do
    stub = stub_request(:post, create_url)
           .with(body: { name: "Metal Mix", description: "Heavy stuff" }.to_json)
           .to_return(status: 201, body: { "id" => "spotify_new_1" }.to_json,
                      headers: { "Content-Type" => "application/json" },)

    described_class.new(user, attributes).call

    expect(stub).to have_been_requested
  end

  it "enables syncing and marks the playlist available" do
    stub_create

    playlist = described_class.new(user, attributes).call

    expect(playlist.sync_enabled).to be(true)
    expect(playlist.available_on_spotify).to be(true)
  end

  it "leaves no local record when Spotify rejects the create" do
    stub_create(status: 500, body: { "error" => "boom" })

    expect { described_class.new(user, attributes).call }.to raise_error(Spotify::ApiError)
    expect(Playlist.count).to eq(0)
  end

  it "surfaces a rate limit without creating a local record" do
    stub_request(:post, create_url).to_return(status: 429, headers: { "Retry-After" => "12" })

    expect { described_class.new(user, attributes).call }.to raise_error(Spotify::RateLimitError)
    expect(Playlist.count).to eq(0)
  end

  it "does not call Spotify when the local record is invalid" do
    stub = stub_create

    expect { described_class.new(user, attributes.merge(name: "")).call }
      .to raise_error(ActiveRecord::RecordInvalid)

    expect(stub).not_to have_been_requested
  end

  it "raises without a local record when Spotify is not connected" do
    user.spotify_connection.destroy!
    stub = stub_create

    expect { described_class.new(user.reload, attributes).call }
      .to raise_error(Spotify::AuthenticationError)

    expect(stub).not_to have_been_requested
    expect(Playlist.count).to eq(0)
  end

  it "rejects a description longer than Spotify allows" do
    stub = stub_create

    expect { described_class.new(user, attributes.merge(description: "x" * 301)).call }
      .to raise_error(ActiveRecord::RecordInvalid)

    expect(stub).not_to have_been_requested
  end
end
