# frozen_string_literal: true

require "rails_helper"

RSpec.describe SessionClaim do
  let(:claimant) do
    Class.new do
      include SessionClaim

      public :claim
    end.new
  end

  let(:user) { create(:user) }

  before { create(:sync_session, user: user, status: :running) }

  it "returns nil when the create loses the unique-index race" do
    result = claimant.claim { create(:sync_session, user: user, status: :running) }

    expect(result).to be_nil
  end

  it "returns the record when the create wins" do
    other = create(:user)

    result = claimant.claim { create(:sync_session, user: other, status: :running) }

    expect(result).to be_persisted
  end

  # The regression: on PostgreSQL a constraint violation aborts the whole
  # surrounding transaction, so rescuing it without a savepoint left every later
  # statement in ScheduledRuns::Advancer raising PG::InFailedSqlTransaction.
  it "leaves the surrounding transaction usable after a lost race" do
    run = create(:scheduled_run)

    ActiveRecord::Base.transaction do
      claimant.claim { create(:sync_session, user: user, status: :running) }
      run.update!(stage_completed: 7)
    end

    expect(run.reload.stage_completed).to eq(7)
  end
end
