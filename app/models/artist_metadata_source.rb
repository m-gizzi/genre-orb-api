# frozen_string_literal: true

class ArtistMetadataSource < ApplicationRecord
  REFRESH_TTL = 90.days
  UNMATCHED_RETRY = 30.days
  ERROR_BACKOFF_BASE = 1.hour
  ERROR_BACKOFF_CAP = 7.days
  ERROR_BACKOFF_MAX_EXPONENT = 10
  ERROR_LIMIT = 250

  belongs_to :artist, inverse_of: :metadata_sources

  enum :source, GenreSourced::SOURCES, validate: true
  enum :state, { pending: 0, matched: 1, unmatched: 2, errored: 3 }, validate: true

  scope :due, ->(now = Time.current) { where("retry_after IS NULL OR retry_after <= ?", now) }
  scope :stalest_first, -> { order(Arel.sql("retry_after ASC NULLS FIRST"), :id) }

  def record_match!(external_id:, external_url: nil)
    update!(state: :matched, external_id: external_id, external_url: external_url,
            attempted_at: Time.current, retry_after: nil, failure_count: 0, last_error: nil,)
  end

  def record_fetch!(external_id: nil, external_url: nil)
    now = Time.current
    update!(state: :matched, external_id: external_id || self.external_id,
            external_url: external_url || self.external_url,
            attempted_at: now, fetched_at: now, retry_after: REFRESH_TTL.from_now,
            failure_count: 0, last_error: nil,)
  end

  def record_unmatched!
    update!(state: :unmatched, external_id: nil, attempted_at: Time.current,
            retry_after: UNMATCHED_RETRY.from_now, failure_count: 0, last_error: nil,)
  end

  def record_failure!(exception)
    failures = failure_count + 1
    update!(state: :errored, attempted_at: Time.current, failure_count: failures,
            last_error: exception.message.to_s.truncate(ERROR_LIMIT),
            retry_after: backoff_for(failures).from_now,)
  end

  private

  def backoff_for(failures)
    exponent = [failures - 1, ERROR_BACKOFF_MAX_EXPONENT].min
    [ERROR_BACKOFF_BASE * (2**exponent), ERROR_BACKOFF_CAP].min
  end
end
