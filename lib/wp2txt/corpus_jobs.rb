# frozen_string_literal: true

require "time"
require_relative "corpus"

module Wp2txt
  # In-process job manager for long-running corpus extractions (MCP server).
  # Each job runs in its own thread with its own Corpus instance (separate
  # SQLite connections and reader), so it never contends with the main
  # request thread. Jobs are lost when the server exits (documented v1 limit).
  class CorpusJobManager
    # @param corpus_factory [#call] returns a fresh Corpus for each job
    def initialize(corpus_factory)
      @factory = corpus_factory
      @jobs = {}
      @mutex = Mutex.new
      @seq = 0
    end

    # Start an extraction job. params are Corpus#extract_corpus keywords.
    # @return [Hash] { job_id:, status: "running" }
    def start_extract(params)
      job_id = @mutex.synchronize { format("job-%04d", @seq += 1) }
      state = {
        job_id: job_id, status: "running", started_at: Time.now.utc.iso8601,
        params: params, titles_done: 0, titles_total: nil, cancel: false
      }
      @mutex.synchronize { @jobs[job_id] = state }

      thread = Thread.new do
        corpus = @factory.call
        begin
          result = corpus.extract_corpus(
            **params,
            max_articles: nil,
            progress: lambda { |done, total|
              update(job_id) { |s| s[:titles_done] = done; s[:titles_total] = total }
            },
            cancel_check: -> { read(job_id)[:cancel] }
          )
          update(job_id) { |s| s[:status] = "completed"; s[:result] = result; s[:finished_at] = Time.now.utc.iso8601 }
        rescue Corpus::Cancelled
          update(job_id) { |s| s[:status] = "cancelled"; s[:finished_at] = Time.now.utc.iso8601 }
        rescue StandardError => e
          update(job_id) { |s| s[:status] = "error"; s[:error] = "#{e.class}: #{e.message}"; s[:finished_at] = Time.now.utc.iso8601 }
        ensure
          corpus.close
        end
      end
      thread.report_on_exception = false
      update(job_id) { |s| s[:thread] = thread }

      { job_id: job_id, status: "running" }
    end

    # @return [Hash, nil] public job state (no thread object), nil if unknown
    def status(job_id)
      state = read(job_id)
      return nil unless state

      public_view(state)
    end

    # Request cancellation; takes effect at the next batch boundary
    def cancel(job_id)
      state = read(job_id)
      return nil unless state

      update(job_id) { |s| s[:cancel] = true }
      { job_id: job_id, status: state[:status], cancel_requested: true }
    end

    def list
      @mutex.synchronize { @jobs.values.map { |s| public_view(s) } }
    end

    private

    def read(job_id)
      @mutex.synchronize { @jobs[job_id] }
    end

    def update(job_id)
      @mutex.synchronize do
        state = @jobs[job_id]
        yield state if state
      end
    end

    def public_view(state)
      view = state.reject { |k, _v| %i[thread cancel].include?(k) }
      if state[:titles_total] && state[:titles_total].positive?
        view[:progress] = (state[:titles_done].to_f / state[:titles_total]).round(3)
      end
      view
    end
  end
end
