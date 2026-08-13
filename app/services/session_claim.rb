# frozen_string_literal: true

# Session creates race against a partial unique index, and losing that race means
# "someone else got there first", not "this failed". The savepoint is what makes
# the rescue safe: these initializers also run inside ScheduledRuns::Advancer's
# row lock, and on PostgreSQL a constraint violation aborts the whole surrounding
# transaction, so rescuing it without one leaves every later statement raising
# PG::InFailedSqlTransaction.
module SessionClaim
  private

  def claim(&)
    ActiveRecord::Base.transaction(requires_new: true, &)
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
