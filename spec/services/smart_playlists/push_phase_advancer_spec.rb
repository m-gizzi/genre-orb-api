# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::PushPhaseAdvancer do
  let(:user) { create(:user) }
  let(:held) { create(:track) }
  let(:wanted) { create_list(:track, 2) }
  let(:target) { create(:playlist, :with_spotify, :holding, user: user, tracks: [held]) }
  let(:smart_playlist) { create(:smart_playlist, :with_rules, target_playlist: target) }

  let(:desired) { wanted }

  let(:version) do
    PlaylistVersion.create_for_push!(target).tap do |built|
      SmartPlaylists::PushVersionTrackBuilder.new(built).call(
        desired.map { |track| SmartPlaylists::PushTrackSet::Entry.new(track_id: track.id, added_at: Time.current) },
      )
    end
  end

  let(:session) do
    create(:push_session, :running, :pinned, smart_playlist: smart_playlist, playlist_version: version,
                                             total_remove_batches: 1, total_add_batches: 5,)
  end

  let(:advancer) { described_class.new(session) }

  describe "#start_add_phase" do
    it "enqueues one job per slice of the tracks still missing" do
      expect { advancer.start_add_phase }.to have_enqueued_job(PlaylistTrackAdditionJob)
        .with(push_session_id: session.id, spotify_ids: wanted.map(&:spotify_id))
    end

    it "commits the total it actually enqueued, so the finalizer's target is reachable" do
      advancer.start_add_phase

      expect(session.reload.total_add_batches).to eq(1)
    end

    it "fans out once even when the batch that closed the remove phase is redelivered" do
      advancer.start_add_phase

      expect { described_class.new(session.reload).start_add_phase }
        .not_to have_enqueued_job(PlaylistTrackAdditionJob)
    end

    it "records when the add phase was claimed" do
      expect { advancer.start_add_phase }.to change { session.reload.add_phase_started_at }.from(nil)
    end

    it "releases the claim when the fan-out fails, so the retry can take it" do
      allow(ActiveJob).to receive(:perform_all_later).and_raise("redis is down")

      expect { advancer.start_add_phase }.to raise_error("redis is down")
      expect(session.reload.add_phase_started_at).to be_nil
    end

    context "when the diff leaves nothing to add" do
      let(:desired) { [held] }

      it "finalizes instead of waiting on a batch that will never be enqueued" do
        advancer.start_add_phase

        expect(session.reload).to be_completed
        expect(session.total_add_batches).to eq(0)
      end
    end

    context "when a sync swaps the target's current version mid-push" do
      it "keeps diffing against the pinned baseline" do
        create(:playlist_version, :current, playlist: target)

        expect { advancer.start_add_phase }.to have_enqueued_job(PlaylistTrackAdditionJob)
          .with(push_session_id: session.id, spotify_ids: wanted.map(&:spotify_id)).once
        expect(session.reload.total_add_batches).to eq(1)
      end
    end
  end
end
