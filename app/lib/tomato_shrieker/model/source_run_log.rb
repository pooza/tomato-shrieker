require 'sequel/model'

module TomatoShrieker
  class SourceRunLog < Sequel::Model(:source_run_log)
    include Package

    STATUS_SUCCESS = 'success'.freeze
    STATUS_ERROR = 'error'.freeze

    dataset_module do
      def latest_for(source_id)
        return where(source_id:).order(Sequel.desc(:executed_at)).first
      end
    end

    def self.record_success(source_id, started_at:)
      create(
        source_id:,
        executed_at: started_at,
        status: STATUS_SUCCESS,
        duration_ms: duration_ms(started_at),
      )
    rescue => e
      Sentry.capture_exception(e) if Sentry.initialized?
    end

    def self.record_error(source_id, started_at:, error:)
      create(
        source_id:,
        executed_at: started_at,
        status: STATUS_ERROR,
        error_message: "#{error.class}: #{error.message}",
        duration_ms: duration_ms(started_at),
      )
    rescue => e
      Sentry.capture_exception(e) if Sentry.initialized?
    end

    def self.prune(retention_days)
      cutoff = Time.now - (retention_days * 86_400)
      return where(Sequel.lit('executed_at < ?', cutoff)).delete
    end

    def self.duration_ms(started_at)
      return ((Time.now - started_at) * 1000).to_i
    end
  end
end
