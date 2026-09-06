# frozen_string_literal: true

module ProviderIntegrator
  # Ordered sink for diagnostics. Analyzers append through #add (which renders the registry template)
  # and the pipeline reads #sorted, whose order is part of the IR contract (docs/IR_CONTRACT.md 3):
  # error before warning before info, then code, location and message.
  class EventLog
    LEVEL_RANK = { "error" => 0, "warning" => 1, "info" => 2 }.freeze

    def initialize(events = [])
      @events = events.to_a.dup
    end

    # Builds an event from the registry and appends it; returns the event.
    def add(code, location: nil, **details)
      event = Events.build(code, location:, **details)
      @events << event
      event
    end

    # Appends an already-built event (used when a sub-result is merged into a bigger one).
    def <<(event)
      @events << event
      self
    end

    # Appends every event of +other+ (an EventLog or an Array).
    def concat(other)
      @events.concat(other.to_a)
      self
    end

    # Events in the order they were emitted.
    def to_a = @events.dup

    # Events in canonical IR order, with exact duplicates collapsed (the same code, location and
    # message twice carries no extra information; two events differing in any of them are kept).
    def sorted
      @events.uniq { |event| [event.code, event.location, event.message] }
             .sort_by { |event| [LEVEL_RANK.fetch(event.level), event.code, event.location.to_s, event.message] }
    end

    def error? = @events.any?(&:error?)
    def empty? = @events.empty?
    def size = @events.size

    # True when an event with +code+ was emitted.
    def include?(code) = @events.any? { |event| event.code == code }

    # All events with +code+.
    def with_code(code) = @events.select { |event| event.code == code }
  end
end
