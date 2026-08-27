module Registry
  # The visitor-facing read of a version's capability fingerprint — the iOS
  # privacy-label treatment: what a plugin runs, where it connects, what it
  # touches. The stored fingerprint is review bookkeeping (argv and call-site
  # digests exist so ANY change trips the growth hold) and renders as noise,
  # so digest entries are dropped here and digest-only dimensions collapse to
  # call-site counts. Admin inspection keeps the raw fingerprint.
  class CapabilitySummary
    PREVIEW_ITEMS = 6

    Row = Struct.new(:label, :items, :code) do
      def code? = code
      def preview = items.first(PREVIEW_ITEMS)
      def hidden = items.drop(PREVIEW_ITEMS)
    end

    # Growth-detection bookkeeping, meaningless to a reader: argv:/cmd:
    # digests, capped-list overflow markers, "bash -c #abcd1234" payloads.
    INTERNAL_ENTRY = /\A(?:argv:|cmd:|overflow:)|\s-c\s#\h+\z/

    DYNAMIC_DIMENSIONS = {
      "dynamic_exec" => "commands",
      "dynamic_network" => "network destinations",
      "dynamic_paths" => "file paths"
    }.freeze

    def initialize(fingerprint)
      @fingerprint = fingerprint.to_h
    end

    def rows
      @rows ||= [
        runs_row,
        Row.new("Executes", visible("shell_digests").map { |s| s.sub(/#\h+\z/, "") }, true),
        Row.new("Connects to", visible("network"), true),
        Row.new("Accesses", visible("paths"), true),
        Row.new("Writes to", visible("writes"), true),
        Row.new("Registers", @fingerprint["keybindings"] ? [ "keyboard shortcuts" ] : [], false),
        Row.new("Computed at runtime", dynamic_items, false)
      ].select { |row| row.items.any? }
    end

    def empty? = rows.empty?

    private

    def visible(dimension)
      Array(@fingerprint[dimension]).map(&:to_s).grep_v(INTERNAL_ENTRY)
    end

    # The shell extractor over-collects by design (function names, heredoc
    # words — everything counts toward growth). Everything stays visible
    # behind the disclosure, but binary-shaped names rank first so the
    # preview shows signal, not the alphabet.
    def runs_row
      commands = visible("processes").reject { |p| p.start_with?("-") || p.match?(/\A[\d.]+\z/) }
      commands = commands.sort_by do |c|
        [ c.match?(/\A[a-z][a-z0-9+-]*\z/) ? (c.include?("-") ? 0 : 1) : 2, c ]
      end
      Row.new("Runs", commands, true)
    end

    def dynamic_items
      DYNAMIC_DIMENSIONS.filter_map do |dimension, noun|
        count = site_count(dimension)
        "#{noun} — #{count} call #{"site".pluralize(count)}" if count.positive?
      end
    end

    # Past the storage cap the list ends with "overflow:<digest> (N total)";
    # N is the true site count.
    def site_count(dimension)
      entries = Array(@fingerprint[dimension]).map(&:to_s)
      overflow = entries.find { |e| e.match?(/\Aoverflow:/) }
      return $1.to_i if overflow&.match(/\((\d+) total\)/)
      entries.size
    end
  end
end
