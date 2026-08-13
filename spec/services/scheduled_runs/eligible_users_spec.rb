# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledRuns::EligibleUsers do
  def connected_user(**connection_attributes)
    user = create(:user)
    create(:service_connection, user: user, **connection_attributes)
    user
  end

  it "includes a connected user with a syncable playlist" do
    user = connected_user
    create(:playlist, :with_spotify, :sync_enabled, user: user)

    expect(described_class.call).to contain_exactly(user)
  end

  it "excludes a user without a Spotify connection" do
    user = create(:user)
    create(:playlist, :with_spotify, :sync_enabled, user: user)

    expect(described_class.call).to be_empty
  end

  it "excludes a user whose connection needs reauthorizing" do
    user = connected_user(needs_reauth: true)
    create(:playlist, :with_spotify, :sync_enabled, user: user)

    expect(described_class.call).to be_empty
  end

  it "excludes a user with no sync-enabled playlists" do
    user = connected_user
    create(:playlist, :with_spotify, user: user)

    expect(described_class.call).to be_empty
  end

  it "excludes a user whose only syncable playlist is gone from Spotify" do
    user = connected_user
    create(:playlist, :with_spotify, :sync_enabled, user: user, available_on_spotify: false)

    expect(described_class.call).to be_empty
  end

  it "returns a user once however many playlists they have" do
    user = connected_user
    create_list(:playlist, 3, :with_spotify, :sync_enabled, user: user)

    expect(described_class.call.count).to eq(1)
  end
end
