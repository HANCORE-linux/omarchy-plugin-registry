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

    # Benign asset types allowed through unscanned — but only when the content
    # actually matches the claimed type. A script named icon.png is a payload.
    ASSET_MAGIC = {
      ".png" => [ "\x89PNG".b ],
      ".jpg" => [ "\xFF\xD8\xFF".b ],
      ".jpeg" => [ "\xFF\xD8\xFF".b ],
      ".gif" => [ "GIF87a".b, "GIF89a".b ],
      ".webp" => [ "RIFF".b ],
      ".ico" => [ "\x00\x00\x01\x00".b, "\x00\x00\x02\x00".b ],
      ".ttf" => [ "\x00\x01\x00\x00".b, "true".b ],
      ".otf" => [ "OTTO".b ],
      ".woff" => [ "wOFF".b ],
      ".woff2" => [ "wOF2".b ],
      ".mp3" => [ "ID3".b, "\xFF\xFB".b, "\xFF\xF3".b, "\xFF\xF2".b ],
      ".wav" => [ "RIFF".b ],
      ".ogg" => [ "OggS".b ]
    }.freeze

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
          if text_like?(content)
            text = content.dup.force_encoding(Encoding::UTF_8)
            text = text.scrub unless text.valid_encoding?
            scan_file(path, text.delete_prefix("\uFEFF"))
          else
            # Binary bytes hiding behind a code extension: pattern rules can't
            # see into it, so a human must.
            findings << Finding.new("binary-in-text-extension", :flag, path,
              "content is binary despite a #{File.extname(path)} extension")
          end
        elsif genuine_asset?(path, content)
          # Polyglots: a valid asset header with executable content behind it
          # still runs if invoked. Flag embedded executable images outright,
          # then run the pattern rules over the bytes (entropy excepted \u2014
          # compressed image data is always high-entropy).
          if content.byteslice(0, 64.kilobytes).to_s.b.match?(/\x7fELF|(?<!^)MZ\x90\x00/n)
            findings << Finding.new("polyglot-executable", :flag, path,
              "asset contains an embedded executable image")
          end
          scan_file(path, content.dup.force_encoding(Encoding::UTF_8).scrub, entropy: false, strict: false)
        else
          # Unscannable non-asset content ships anyway \u2014 never unreviewed.
          findings << Finding.new("binary-payload", :flag, path,
            "file is not a scannable type or a recognizable asset (#{File.extname(path).presence || 'no extension'}); a human must look")
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

    def genuine_asset?(path, content)
      magics = ASSET_MAGIC[File.extname(path).downcase]
      return false if magics.nil?
      head = content.byteslice(0, 8).to_s.b
      magics.any? { |magic| head.start_with?(magic) }
    end

    # Valid UTF-8 with a high printable ratio — what a real source file looks like.
    def text_like?(content)
      sample = content.byteslice(0, 8.kilobytes).to_s.dup.force_encoding(Encoding::UTF_8)
      return false unless sample.valid_encoding?
      return true if sample.empty?
      printable = sample.count("\t\n\r -~") + sample.chars.count { |c| c.ord > 127 }
      printable.fdiv(sample.length) > 0.9
    end

    def scannable?(path, content)
      ext = File.extname(path).downcase
      return true if TEXT_EXTENSIONS.include?(ext)
      return true if PLAIN_FILENAMES.include?(File.basename(path, ".*").downcase)
      return true if ext.empty? && content.byteslice(0, 256).to_s.start_with?("#!")
      false
    end

    # strict: false is the asset-polyglot pass — binary data can innocently
    # decode to control codepoints, so nothing auto-rejects there, it only flags.
    def scan_file(path, text, entropy: true, strict: true)
      check path, text, "invisible-unicode", strict ? :fail : :flag, INVISIBLE_UNICODE,
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
      check path, text, "embedded-shebang", :flag, /\n#!\s*\/(bin|usr)\//, "script payload embedded past the file header" if !entropy
      check_entropy(path, text) if entropy
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
