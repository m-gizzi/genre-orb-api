# frozen_string_literal: true

require "rails_helper"

RSpec.describe Spotify::ArtistMetadataSyncInitializer do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user, sync_all: sync_all) }
  let(:sync_all) { false }

  describe "#call" do
    context "when Spotify is not connected" do
      before { create(:artist, :in_library, user: user, metadata_fetched_at: nil) }

      it "returns a spotify_not_connected outcome" do
        expect(service.call.outcome).to eq(:spotify_not_connected)
      end

      it "does not create a session" do
        expect { service.call }.not_to change(ArtistMetadataSession, :count)
      end
    end

    context "when Spotify is connected" do
      before { create(:service_connection, user: user) }

      context "with no artists to sync" do
        it "returns a no_artists outcome" do
          expect(service.call.outcome).to eq(:no_artists)
        end

        it "does not create a session" do
          expect { service.call }.not_to change(ArtistMetadataSession, :count)
        end
      end

      context "when unfetched artists belong to another user's library" do
        before { create(:artist, :in_library, user: create(:user), metadata_fetched_at: nil) }

        it "returns a no_artists outcome" do
          expect(service.call.outcome).to eq(:no_artists)
        end
      end

      context "when a sync is already in progress" do
        before do
          create(:artist, :in_library, user: user, metadata_fetched_at: nil)
          create(:artist_metadata_session, user: user)
        end

        it "returns an already_in_progress outcome" do
          expect(service.call.outcome).to eq(:already_in_progress)
        end

        it "does not create another session" do
          expect { service.call }.not_to change(ArtistMetadataSession, :count)
        end
      end

      context "with artists that need metadata" do
        let!(:unfetched_artists) { Array.new(3) { create(:artist, :in_library, user: user, metadata_fetched_at: nil) } }
        let!(:fetched_artist) { create(:artist, :in_library, user: user, metadata_fetched_at: 1.day.ago) }

        it "returns a started outcome" do
          expect(service.call).to be_started
        end

        it "creates an artist metadata session" do
          expect { service.call }.to change(ArtistMetadataSession, :count).by(1)
        end

        it "returns the created session" do
          result = service.call
          expect(result.session).to be_a(ArtistMetadataSession)
          expect(result.session.user).to eq(user)
        end

        it "sets session to running" do
          expect(service.call.session.status).to eq("running")
        end

        it "sets correct total_batches" do
          expect(service.call.session.total_batches).to eq(1)
        end

        it "returns batches with only unfetched artist ids" do
          result = service.call
          expect(result.batches.flatten).to match_array(unfetched_artists.map(&:id))
        end

        it "does not include already fetched artists" do
          result = service.call
          expect(result.batches.flatten).not_to include(fetched_artist.id)
        end

        it "enqueues a batch fetch job" do
          expect { service.call }.to have_enqueued_job(ArtistBatchFetchJob)
        end
      end

      context "with sync_all: true" do
        let(:sync_all) { true }
        let!(:unfetched_artists) { Array.new(2) { create(:artist, :in_library, user: user, metadata_fetched_at: nil) } }
        let!(:fetched_artists) do
          Array.new(2) do
            create(:artist, :in_library, user: user, metadata_fetched_at: 1.day.ago)
          end
        end

        it "includes all artists regardless of metadata_fetched_at" do
          result = service.call
          all_ids = (unfetched_artists + fetched_artists).map(&:id)
          expect(result.batches.flatten).to match_array(all_ids)
        end
      end

      context "with more artists than batch size" do
        before do
          # More than the 50-artist batch limit.
          create(:track, :in_library, :with_artists, user: user, artist_count: 120)
        end

        it "splits into multiple batches" do
          expect(service.call.batches.size).to eq(3) # 50 + 50 + 20
        end

        it "sets correct total_batches on session" do
          expect(service.call.session.total_batches).to eq(3)
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
          create(:track, :in_library, :with_artists, user: user, artist_count: 50)
        end

        it "creates single batch" do
          expect(service.call.batches.size).to eq(1)
        end
      end
    end
  end
end
