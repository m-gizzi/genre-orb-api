# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScheduledRuns::Advancer do
  let(:user) do
    create(:user).tap do |record|
      create(:service_connection, user: record)
      create(:playlist, :with_spotify, :sync_enabled, user: record)
    end
  end

  let(:run) { create(:scheduled_run, stage_total: 1, stage_completed: 0) }

  # Both created before any travel_to, so their timestamps are the real "now".
  before do
    user
    run
  end

  # Not a memoized subject: several examples tick more than once.
  def tick
    described_class.new(run.reload).call
  end

  describe "the discovery stage" do
    it "waits while a playlist fetch is outstanding" do
      tick

      expect(run.reload.stage).to eq("discovery")
    end

    it "moves to the library sync stage once every fetch has reported" do
      run.discovery_completed!

      tick

      expect(run.reload.stage).to eq("library_sync")
      expect(run.sync_sessions).to be_any
    end

    it "gives up after the stage timeout and records why" do
      travel_to(ScheduledRun::STAGE_TIMEOUTS.fetch("discovery").from_now + 1.minute) { tick }

      expect(run.reload.stage).to eq("library_sync")
      expect(run.stage_errors).to have_key("discovery")
    end
  end

  describe "the library sync stage" do
    let(:run) { create(:scheduled_run, :library_sync) }
    let!(:session) { create(:sync_session, user: user, scheduled_run: run, status: :running) }

    it "waits while a sync session is active" do
      tick

      expect(run.reload.stage).to eq("library_sync")
    end

    it "starts the global artist sync once every session is terminal" do
      create(:artist, metadata_fetched_at: nil)
      session.update!(status: :completed, completed_at: Time.current)

      tick

      expect(run.reload.stage).to eq("artist_metadata")
      expect(run.artist_metadata_sessions.global).to be_any
    end

    it "ignores a session it did not start" do
      session.update!(scheduled_run: nil)

      tick

      expect(run.reload.stage).to eq("artist_metadata")
    end

    it "fails the stragglers on timeout rather than leaving them holding the index" do
      travel_to(ScheduledRun::STAGE_TIMEOUTS.fetch("library_sync").from_now + 1.minute) { tick }

      expect(session.reload).to be_failed
      expect(run.reload.stage_errors).to have_key("library_sync")
    end
  end

  describe "the artist metadata stage" do
    let(:run) { create(:scheduled_run, :artist_metadata) }
    let!(:session) { create(:artist_metadata_session, user: nil, scheduled_run: run, status: :running) }

    it "waits while the global session is active" do
      tick

      expect(run.reload.stage).to eq("artist_metadata")
    end

    it "moves on to the pushes once it finishes" do
      session.update!(status: :completed, completed_at: Time.current)

      tick

      expect(run.reload.stage).to eq("pushes")
    end

    it "fails the session on timeout" do
      travel_to(ScheduledRun::STAGE_TIMEOUTS.fetch("artist_metadata").from_now + 1.minute) { tick }

      expect(session.reload).to be_failed
      expect(run.reload.stage_errors).to have_key("artist_metadata")
    end
  end

  describe "the push stage" do
    let(:run) { create(:scheduled_run, :artist_metadata) }
    let!(:upstream) { create(:smart_playlist, :enabled, user: user) }
    let!(:downstream) do
      create(:smart_playlist, :enabled, user: user, source_playlists: [upstream.target_playlist])
    end

    def enter_push_stage
      tick
    end

    it "plans the waves in dependency order and starts only the first" do
      enter_push_stage

      expect(run.reload.push_plan).to eq([[upstream.id], [downstream.id]])
      expect(run.push_sessions.pluck(:smart_playlist_id)).to eq([upstream.id])
    end

    it "starts the next wave once the previous one is terminal" do
      enter_push_stage
      run.push_sessions.each { |session| session.update!(status: :completed, completed_at: Time.current) }

      tick

      expect(run.reload.push_wave).to eq(1)
      expect(run.push_sessions.pluck(:smart_playlist_id)).to contain_exactly(upstream.id, downstream.id)
    end

    it "completes the run when the last wave finishes" do
      enter_push_stage
      2.times do
        run.reload.push_sessions.each { |session| session.update!(status: :completed, completed_at: Time.current) }
        tick
      end

      expect(run.reload).to have_attributes(status: "completed", completed_at: be_present)
    end

    it "ends with completed_with_errors when a stage was abandoned" do
      run.record_stage_error!(:library_sync, "timed out")
      enter_push_stage
      2.times do
        run.reload.push_sessions.each { |session| session.update!(status: :completed, completed_at: Time.current) }
        tick
      end

      expect(run.reload.status).to eq("completed_with_errors")
    end

    it "abandons a wave that overruns its own timeout" do
      enter_push_stage
      session = run.push_sessions.sole

      travel_to(ScheduledRun::STAGE_TIMEOUTS.fetch("pushes").from_now + 1.minute) { tick }

      expect(session.reload).to be_failed
      expect(run.reload).to have_attributes(push_wave: 1, stage_errors: have_key("pushes_wave_0"))
    end
  end

  describe "the hard cap" do
    let(:run) { create(:scheduled_run, :library_sync, started_at: Time.current) }

    it "stops a run that outlives it, whatever stage it is in" do
      travel_to(ScheduledRun::HARD_CAP.from_now + 1.minute) { tick }

      expect(run.reload).to have_attributes(status: "completed_with_errors", stage: "library_sync")
      expect(run.stage_errors).to have_key("hard_cap")
    end
  end

  it "does nothing to a run that is not running" do
    run.update!(status: :pending)

    tick

    expect(run.reload.stage).to eq("discovery")
  end
end
