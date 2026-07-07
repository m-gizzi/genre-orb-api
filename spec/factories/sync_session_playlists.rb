# frozen_string_literal: true

FactoryBot.define do
  factory :sync_session_playlist do
    sync_session
    playlist
    status { :pending }
    total_pages { 0 }
    completed_pages { 0 }

    trait :fetching do
      status { :fetching_pages }
      started_at { Time.current }
      total_pages { 10 }
      completed_pages { 5 }
    end

    trait :completed do
      status { :completed }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      total_pages { 10 }
      completed_pages { 10 }
    end

    trait :failed do
      status { :failed }
      started_at { 1.hour.ago }
      completed_at { Time.current }
      error_message { "Page fetch failed" }
    end

    trait :skipped do
      status { :skipped }
      completed_at { Time.current }
      total_pages { 0 }
      completed_pages { 0 }
    end
  end
end
