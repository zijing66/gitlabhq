# frozen_string_literal: true

module Packages
  module CleanupArtifactWorker
    extend ActiveSupport::Concern
    include LimitedCapacity::Worker
    include Gitlab::Utils::StrongMemoize

    def perform_work
      return unless artifact

      log_metadata(artifact)

      artifact.destroy!
    rescue StandardError
      artifact&.error!
    end

    def remaining_work_count
      artifacts_pending_destruction.limit(max_running_jobs + 1).count
    end

    private

    def model
      raise NotImplementedError
    end

    def log_metadata
      raise NotImplementedError
    end

    def log_cleanup_item
      raise NotImplementedError
    end

    def artifact
      strong_memoize(:artifact) do
        model.transaction do
          to_delete = next_item

          if to_delete
            to_delete.processing!
            log_cleanup_item(to_delete)
          end

          to_delete
        end
      end
    end

    def artifacts_pending_destruction
      model.pending_destruction
    end

    def next_item
      model.next_pending_destruction(order_by: :updated_at)
    end
  end
end
