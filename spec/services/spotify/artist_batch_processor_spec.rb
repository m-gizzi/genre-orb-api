# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::ArtistBatchProcessor do
  let(:user) { create(:user) }
  let(:session) do
    create(
      :artist_metadata_session,
      user: user,
      status: :running,
      total_batches: 3,
      completed_batches: 0,
    )
  end
  let(:artists) { create_list(:artist, 2) }
  let(:artist_ids) { artists.map(&:id) }
  let(:adapter) { instance_spy(SpotifyAdapter) }
  let(:service) { described_class.new(session, artist_ids: artist_ids, adapter: adapter) }

  let(:api_response) do
    {
      "artists" => artists.map do |artist|
        {
          "id" => artist.spotify_id,
          "name" => artist.name,
          "genres" => %w[pop rock],
          "popularity" => 75,
          "images" => [{ "url" => "https://example.com/artist.jpg" }],
        }
      end,
    }
  end

  before do
    create(:service_connection, user: user)
    allow(adapter).to receive(:artists).and_return(api_response)
  end

  describe "#call" do
    it "returns success result" do
      result = service.call
      expect(result.success?).to be(true)
    end

    it "returns skipped as false" do
      result = service.call
      expect(result.skipped?).to be(false)
    end

    it "fetches artists from Spotify API" do
      spotify_ids = artists.map(&:spotify_id)
      service.call
      expect(adapter).to have_received(:artists).with(spotify_ids)
    end

    it "increments completed_batches on session" do
      expect { service.call }.to change { session.reload.completed_batches }.by(1)
    end

    context "when session is already failed" do
      let(:session) { create(:artist_metadata_session, :failed, user: user) }

      it "returns skipped result" do
        result = service.call
        expect(result.skipped?).to be(true)
      end

      it "does not call the Spotify API" do
        service.call
        expect(adapter).not_to have_received(:artists)
      end
    end

    context "when artist_ids is empty" do
      let(:artist_ids) { [] }

      it "returns skipped result" do
        result = service.call
        expect(result.skipped?).to be(true)
      end

      it "does not call the Spotify API" do
        service.call
        expect(adapter).not_to have_received(:artists)
      end
    end

    context "when artist_ids do not match any records" do
      let(:artist_ids) { [999_999, 999_998] }

      it "returns skipped result" do
        result = service.call
        expect(result.skipped?).to be(true)
      end
    end

    context "when this is the final batch" do
      let(:session) do
        create(
          :artist_metadata_session,
          user: user,
          status: :running,
          total_batches: 2,
          completed_batches: 1,
        )
      end

      it "returns session_completed as true" do
        result = service.call
        expect(result.session_completed?).to be(true)
      end

      it "marks session as completed" do
        service.call
        expect(session.reload.status).to eq("completed")
      end

      it "sets completed_at timestamp" do
        service.call
        expect(session.reload.completed_at).to be_within(1.second).of(Time.current)
      end
    end

    context "when more batches remain" do
      let(:session) do
        create(
          :artist_metadata_session,
          user: user,
          status: :running,
          total_batches: 5,
          completed_batches: 1,
        )
      end

      it "returns session_completed as false" do
        result = service.call
        expect(result.session_completed?).to be(false)
      end

      it "does not mark session as completed" do
        service.call
        expect(session.reload.status).to eq("running")
      end
    end
  end
end
