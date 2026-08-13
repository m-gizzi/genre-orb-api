# frozen_string_literal: true

FactoryBot.define do
  factory :scheduled_run do
    run_date { ScheduledRun.date_for }
    status { :running }
    stage { :discovery }
    stage_started_at { Time.current }
    started_at { Time.current }

    trait :library_sync do
      stage { :library_sync }
    end

    trait :artist_metadata do
      stage { :artist_metadata }
    end

    trait :pushes do
      stage { :pushes }
    end

    trait :completed do
      status { :completed }
      completed_at { Time.current }
    end
  end
end
