# frozen_string_literal: true

require "rails_helper"

RSpec.describe SmartPlaylists::PushPlanner do
  let(:user) { create(:user) }
  let!(:connection) { create(:service_connection, user: user) }
  let(:adapter) { SpotifyAdapter.new(connection) }
  let(:any_rules) do
    { "match" => "all", "rules" => [{ "field" => "genre", "operator" => "equals", "value" => "rock" }] }
  end

  let(:desired_tracks) { create_list(:track, 3, :with_genres, genre_names: ["rock"]) }
  let(:source) { create(:playlist, :holding, user: user, tracks: desired_tracks) }

  def build_target(holding: [], snapshot: nil)
    create(:playlist, :with_spotify, :holding, user: user, tracks: holding, version_snapshot_id: snapshot)
  end

  def smart_playlist_for(target, rules: any_rules)
    create(:smart_playlist, target_playlist: target, rules: rules, source_playlists: [source])
  end

  def plan(smart_playlist)
    session = create(:push_session, :running, smart_playlist: smart_playlist)
    described_class.new(session, adapter: adapter).call
    session.reload
  end

  def stub_snapshot(target, snapshot_id)
    stub_request(:get, "#{Spotify::Client::BASE_URL}/playlists/#{target.spotify_id}")
      .with(query: { fields: "snapshot_id" })
      .to_return(status: 200, body: { "snapshot_id" => snapshot_id }.to_json,
                 headers: { "Content-Type" => "application/json" },)
  end

  describe "the snapshot guard" do
    it "diffs when Spotify's snapshot still matches the version we hold" do
      target = build_target(holding: [desired_tracks.first], snapshot: "snap_1")
      stub_snapshot(target, "snap_1")

      session = plan(smart_playlist_for(target))

      expect(session).to be_strategy_diff
    end

    it "replaces when Spotify's snapshot has moved on" do
      target = build_target(holding: [desired_tracks.first], snapshot: "snap_1")
      stub_snapshot(target, "snap_2")

      session = plan(smart_playlist_for(target))

      expect(session).to be_strategy_replace
    end

    it "replaces when the version records no snapshot at all" do
      target = build_target(holding: [desired_tracks.first])
      stub_snapshot(target, "snap_1")

      session = plan(smart_playlist_for(target))

      expect(session).to be_strategy_replace
    end

    it "replaces a never-synced target without asking Spotify" do
      target = create(:playlist, :with_spotify, user: user)
      snapshot_stub = stub_snapshot(target, "snap_1")

      session = plan(smart_playlist_for(target))

      expect(session).to be_strategy_replace
      expect(snapshot_stub).not_to have_been_requested
    end
  end

  describe "choosing between diff and replace on cost" do
    before { stub_const("SmartPlaylists::PushBatches::BATCH_SIZE", 1) }

    it "prefers the diff when the delta is small" do
      target = build_target(holding: desired_tracks.take(2), snapshot: "snap_1")
      stub_snapshot(target, "snap_1")

      session = plan(smart_playlist_for(target))

      expect(session).to be_strategy_diff
      expect(session.total_remove_batches).to eq(0)
      expect(session.total_add_batches).to eq(1)
    end

    it "prefers a clear-and-refill when almost everything churns" do
      target = build_target(holding: create_list(:track, 3), snapshot: "snap_1")
      stub_snapshot(target, "snap_1")

      session = plan(smart_playlist_for(target))

      expect(session).to be_strategy_replace
      expect(session.total_remove_batches).to eq(1)
      expect(session.total_add_batches).to eq(2)
    end
  end

  describe "a replace that fits in one batch" do
    it "seeds the whole playlist in the clearing PUT, with no add phase to follow" do
      target = create(:playlist, :with_spotify, user: user)
      smart_playlist = smart_playlist_for(target)

      session = nil
      expect { session = plan(smart_playlist) }
        .to have_enqueued_job(PlaylistTracksReplaceJob)
        .with(push_session_id: anything, spotify_ids: desired_tracks.map(&:spotify_id))

      expect(session).to be_strategy_replace
      expect(session.total_add_batches).to eq(0)
    end
  end

  describe "the plan it commits" do
    let(:target) { build_target(holding: [desired_tracks.first], snapshot: "snap_1") }

    before { stub_snapshot(target, "snap_1") }

    it "builds a rule-evaluation version holding every match" do
      session = plan(smart_playlist_for(target))

      version = session.playlist_version
      expect(version).to be_source_rule_evaluation
      expect(version).to be_building
      expect(version.tracks).to match_array(desired_tracks)
    end

    it "pins the version the whole plan is measured against" do
      session = plan(smart_playlist_for(target))

      expect(session.baseline_version_id).to eq(target.current_version_id)
    end

    it "keeps its batch counts when a sync swaps current_version mid-push" do
      session = plan(smart_playlist_for(target))
      planned_add_batches = session.total_add_batches

      create(:playlist_version, :current, playlist: target)
      SmartPlaylists::PushPhaseAdvancer.new(session.reload).start_add_phase

      expect(session.reload.total_add_batches).to eq(planned_add_batches)
    end

    it "does not swap the new version in before the push lands" do
      smart_playlist = smart_playlist_for(target)
      previous_version_id = target.current_version_id

      plan(smart_playlist)

      expect(target.reload.current_version_id).to eq(previous_version_id)
    end

    it "records the evaluation on the smart playlist" do
      smart_playlist = smart_playlist_for(target)

      plan(smart_playlist)

      expect(smart_playlist.reload.match_count).to eq(3)
      expect(smart_playlist.last_evaluated_at).to be_present
    end

    it "counts the tracks it will add and remove" do
      session = plan(smart_playlist_for(target))

      expect(session.tracks_added).to eq(2)
      expect(session.tracks_removed).to eq(0)
    end

    it "reports the net change even when the whole playlist is rewritten" do
      stub_const("SmartPlaylists::PushBatches::BATCH_SIZE", 1)
      rewritten = build_target(holding: desired_tracks.take(2), snapshot: "snap_1")
      stub_snapshot(rewritten, "snap_2")

      session = plan(smart_playlist_for(rewritten))

      expect(session).to be_strategy_replace
      expect(session.tracks_added).to eq(1)
      expect(session.tracks_removed).to eq(0)
    end

    it "enqueues one addition job per batch" do
      smart_playlist = smart_playlist_for(target)

      expect { plan(smart_playlist) }.to have_enqueued_job(PlaylistTrackAdditionJob).exactly(:once)
    end

    it "skips the remove phase when there is nothing to remove" do
      smart_playlist = smart_playlist_for(target)

      expect { plan(smart_playlist) }.not_to have_enqueued_job(PlaylistTrackRemovalJob)
    end
  end

  describe "when nothing needs to change" do
    it "finalizes without touching Spotify's track endpoints" do
      target = build_target(holding: desired_tracks, snapshot: "snap_1")
      stub_snapshot(target, "snap_1")

      session = plan(smart_playlist_for(target))

      expect(session).to be_completed
      expect(session.playlist_version).to be_complete
      expect(target.reload.current_version_id).to eq(session.playlist_version_id)
    end

    it "still stamps last_pushed_at" do
      target = build_target(holding: desired_tracks, snapshot: "snap_1")
      stub_snapshot(target, "snap_1")
      smart_playlist = smart_playlist_for(target)

      plan(smart_playlist)

      expect(smart_playlist.reload.last_pushed_at).to be_present
    end
  end

  describe "when the rules match nothing" do
    let(:no_matches) do
      { "match" => "all",
        "rules" => [{ "field" => "title", "operator" => "equals", "value" => "nothing matches this" }], }
    end

    it "skips the session and never calls Spotify" do
      target = build_target(holding: [desired_tracks.first], snapshot: "snap_1")
      snapshot_stub = stub_snapshot(target, "snap_1")

      session = plan(smart_playlist_for(target, rules: no_matches))

      expect(session).to be_skipped
      expect(session.error_message).to eq(I18n.t("api.smart_playlists.push_no_matches"))
      expect(snapshot_stub).not_to have_been_requested
    end

    it "leaves the target's tracks alone" do
      target = build_target(holding: [desired_tracks.first], snapshot: "snap_1")
      stub_snapshot(target, "snap_1")
      previous_version_id = target.current_version_id

      plan(smart_playlist_for(target, rules: no_matches))

      expect(target.reload.current_version_id).to eq(previous_version_id)
    end
  end

  describe "sampling above the push limit" do
    before { stub_const("SmartPlaylists::PushTrackSet::PUSH_LIMIT", 2) }

    it "flags the session and pushes only the sample" do
      target = build_target(holding: [], snapshot: "snap_1")
      stub_snapshot(target, "snap_1")

      session = plan(smart_playlist_for(target))

      expect(session).to be_sampled
      expect(session.match_count).to eq(3)
      expect(session.playlist_version.playlist_version_tracks.count).to eq(2)
    end
  end

  describe "when committing the plan fails partway" do
    let(:target) { build_target(holding: [desired_tracks.first], snapshot: "snap_1") }

    before do
      stub_snapshot(target, "snap_1")
      allow(SmartPlaylists::PushVersionTrackBuilder).to receive(:new).and_raise(ActiveRecord::StatementInvalid)
    end

    it "leaves no orphan version behind for nothing to collect" do
      expect { plan(smart_playlist_for(target)) }.to raise_error(ActiveRecord::StatementInvalid)

      expect(target.playlist_versions.source_rule_evaluation).to be_empty
    end

    it "does not start a push phase" do
      smart_playlist = smart_playlist_for(target)

      expect do
        expect { plan(smart_playlist) }.to raise_error(ActiveRecord::StatementInvalid)
      end.not_to have_enqueued_job(PlaylistTrackAdditionJob)
    end
  end

  describe "re-planning after a retry" do
    it "discards the abandoned version rather than stacking a second one" do
      target = build_target(holding: [desired_tracks.first], snapshot: "snap_1")
      stub_snapshot(target, "snap_1")
      smart_playlist = smart_playlist_for(target)
      session = create(:push_session, :running, smart_playlist: smart_playlist)

      described_class.new(session, adapter: adapter).call
      first_version_id = session.reload.playlist_version_id
      described_class.new(session, adapter: adapter).call

      expect(session.reload.playlist_version_id).not_to eq(first_version_id)
      expect(PlaylistVersion.where(id: first_version_id)).not_to exist
      expect(target.playlist_versions.source_rule_evaluation.count).to eq(1)
    end
  end
end
