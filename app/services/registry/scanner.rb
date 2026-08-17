module Registry
  # Deterministic scanning: GuardDog-style rules tuned for the Omarchy stack
  # (bash + QML/JS), plus metadata anomalies. Runs on every version, every time.
  #
  # Severities:
  #   :fail — rejected automatically, no human in the loop
  #   :flag — quarantined for the admin queue
  class Scanner
    Finding = Struct.new(:rule, :severity, :file, :detail) do
      def as_json(*) = { "rule" => rule, "severity" => severity.to_s, "file" => file, "detail" => detail }
    end

    TEXT_EXTENSIONS = %w[.qml .js .mjs .sh .bash .json .md .txt .yml .yaml .toml .conf .css .svg .xml .html .ini .desktop].freeze

    # Benign asset types allowed through unscanned; anything else unscannable
    # (executables, libraries, archives, unknown binaries) is flagged.
    ASSET_EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .ico .ttf .otf .woff .woff2 .mp3 .wav .ogg].freeze

    # Invisible/bidi characters used to hide code from review (the GlassWorm
    # trick). A leading BOM is stripped before scanning; any other occurrence
    # of these codepoints is malicious-shaped.
    INVISIBLE_UNICODE = /[\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\uFEFF]/

    SUSPICIOUS_HOSTS = %w[
      pastebin.com paste.ee hastebin.com rentry.co
      discord.com/api/webhooks discordapp.com/api/webhooks
      api.telegram.org transfer.sh oshi.at temp.sh
    ].freeze

    attr_reader :findings

    def initialize(tarball, plugin: nil)
      @tarball = tarball
      @plugin = plugin
      @findings = []
    end

    def scan
      @tarball.contents.each do |path, content|
        if scannable?(path, content)
          text = content.dup.force_encoding(Encoding::UTF_8)
          text = text.scrub unless text.valid_encoding?
          scan_file(path, text.delete_prefix("\uFEFF"))
        elsif !ASSET_EXTENSIONS.include?(File.extname(path).downcase)
          # Unscannable non-asset content ships anyway \u2014 never unreviewed.
          findings << Finding.new("binary-payload", :flag, path,
            "file type is not scannable (#{File.extname(path).presence || 'no extension'}); a human must look")
        end
      end
      # Reviewed bytes must be ALL the bytes: anything past the per-file scan
      # cap escaped analysis, so it goes to a human too.
      @tarball.truncated.each do |path|
        findings << Finding.new("scan-truncated", :flag, path,
          "file exceeds the #{Registry::TarballInspector::MAX_SCAN_BYTES / 1.kilobyte}KB scan window \u2014 not fully analyzed")
      end
      scan_metadata
      findings
    end

    def verdict
      return :fail if findings.any? { |f| f.severity == :fail }
      return :flag if findings.any? { |f| f.severity == :flag }
      :pass
    end

    private

    PLAIN_FILENAMES = %w[readme license licence copying notice authors changelog contributing codeowners].freeze

    def scannable?(path, content)
      ext = File.extname(path).downcase
      return true if TEXT_EXTENSIONS.include?(ext)
      return true if PLAIN_FILENAMES.include?(File.basename(path, ".*").downcase)
      return true if ext.empty? && content.byteslice(0, 256).to_s.start_with?("#!")
      false
    end

    def scan_file(path, text)
      check path, text, "invisible-unicode", :fail, INVISIBLE_UNICODE,
        "invisible or bidirectional Unicode characters (code hidden from review)"
      check path, text, "curl-pipe-shell", :flag, /\b(curl|wget)\b[^|\n;]*\|\s*(sudo\s+)?(ba|z|da)?sh\b/,
        "pipes a remote download straight into a shell"
      check path, text, "base64-decode-exec", :flag, /base64\s+(-d|--decode)[^\n]*\|\s*(sudo\s+)?\w*sh\b|eval.{0,40}base64|atob\s*\([^)]*\).{0,40}(eval|Function)/m,
        "decodes base64 and executes it"
      check path, text, "eval-construct", :flag, /\beval\s*\(|new\s+Function\s*\(/,
        "dynamic code evaluation"
      check path, text, "raw-ip-url", :flag, %r{https?://\d{1,3}(\.\d{1,3}){3}},
        "network call to a raw IP address"
      check path, text, "suspicious-host", :flag, /#{SUSPICIOUS_HOSTS.map { |h| Regexp.escape(h) }.join("|")}/,
        "contacts a paste site, webhook, or dead-drop service"
      check path, text, "credential-paths", :flag, %r{(\$HOME|~)/\.(ssh|gnupg|aws|config/gh|mozilla)\b|\.ssh/id_},
        "touches credential or key storage"
      check path, text, "shell-history-tamper", :flag, /HISTFILE=|history\s+-c\b|shred\b.*bash_history/,
        "tampers with shell history"
      check_entropy(path, text)
    end

    # Long high-entropy blobs are the signature of obfuscated payloads.
    def check_entropy(path, text)
      text.scan(/[A-Za-z0-9+\/=_-]{400,}/).each do |blob|
        next if entropy(blob) < 4.5
        findings << Finding.new("obfuscation-entropy", :flag, path,
          "high-entropy blob of #{blob.length} chars (possible packed payload)")
        break
      end
    end

    def scan_metadata
      return unless @plugin&.persisted?
      last = @plugin.versions.published.order(published_at: :desc).first
      if last&.published_at && last.published_at < 6.months.ago
        findings << Finding.new("dormant-plugin-update", :flag, "manifest.json",
          "first update after #{((Time.current - last.published_at) / 1.month).round} months dormant")
      end
    end

    def check(path, text, rule, severity, pattern, detail)
      return unless (match = text.match(pattern))
      findings << Finding.new(rule, severity, path, "#{detail}: #{match[0].to_s.strip.first(80)}")
    end

    def entropy(string)
      freq = string.each_char.tally
      len = string.length.to_f
      -freq.values.sum { |count| p = count / len; p * Math.log2(p) }
    end
  end
end
