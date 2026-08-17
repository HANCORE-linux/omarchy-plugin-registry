module Registry
  # Static extraction of what a plugin *can do*: processes it spawns, hosts it
  # talks to, filesystem reach, keybinding hooks. First release records the
  # fingerprint; an update whose surface GROWS is held for a human (the Flathub
  # model — the only human-review approach that scales).
  class CapabilityFingerprint
    CODE_EXTENSIONS = %w[.qml .js .mjs .sh .bash].freeze

    def self.compute(tarball) = new(tarball).compute

    def initialize(tarball)
      @tarball = tarball
    end

    SHELL_INTERPRETERS = %w[sh bash zsh dash].freeze

    def compute
      processes = Set.new
      hosts = Set.new
      paths = Set.new
      keybindings = false
      dynamic_exec = false

      @tarball.contents.each do |path, content|
        next unless CODE_EXTENSIONS.include?(File.extname(path).downcase)
        text = content.dup.force_encoding(Encoding::UTF_8)
        text = text.scrub unless text.valid_encoding?

        # QML/Quickshell process spawns: Process { command: ["curl", ...] },
        # bar.run("cmd ..."), execDetached(["cmd", ...])
        text.scan(/command:\s*\[\s*["']([^"']+)["']/) { |m| processes << binary_name(m[0]) }
        text.scan(/\b(?:bar\.run|execDetached|startDetached)\s*\(\s*\[?\s*["']([^"']+)["']/) { |m| processes << binary_name(m[0]) }

        # Opaque execution surfaces (fingerprinted so CHANGES count as growth):
        # 1. Non-literal command values — `command: argv` or arrays built from
        #    expressions can run anything.
        dynamic_exec ||= text.match?(/command:\s*(?!\[\s*["'])[a-zA-Z_\[]/)
        # 2. Literal shell -c payloads — the binary name "bash" hides the real
        #    program, so the script itself joins the fingerprint by digest.
        text.scan(/command:\s*\[\s*["'](?:\/[\w\/]*\/)?(#{SHELL_INTERPRETERS.join('|')})["']\s*,\s*["']-c["']\s*,\s*["'](.{0,4000}?)["']\s*\]/m) do |interpreter, script|
          processes << "#{interpreter} -c ##{Digest::SHA256.hexdigest(script).first(8)}"
        end

        # Shell scripts: leading command words on each line
        if %w[.sh .bash].include?(File.extname(path).downcase)
          text.each_line do |line|
            word = line.strip[/\A([a-z0-9_\-\.\/]+)/, 1]
            processes << binary_name(word) if word && !SHELL_NOISE.include?(word)
          end
        end

        text.scan(%r{https?://([a-z0-9.-]+\.[a-z]{2,}|\d{1,3}(?:\.\d{1,3}){3})}i) { |m| hosts << m[0].downcase }
        text.scan(%r{["'](/(?:etc|usr|var|opt|home)[^"'\s]*)["']}) { |m| paths << m[0] }
        keybindings ||= text.match?(/\bShortcut\b|keybinding|GlobalShortcut/i)
      end

      {
        "processes" => processes.reject(&:blank?).sort,
        "network" => hosts.sort,
        "paths" => paths.sort.first(20),
        "keybindings" => keybindings,
        "dynamic_exec" => dynamic_exec
      }
    end

    # An update's fingerprint compared against the last published one.
    # Returns [] when nothing grew; otherwise human-readable additions.
    def self.growth(previous, current)
      return [] if previous.blank?
      additions = []
      %w[processes network paths].each do |dimension|
        added = Array(current[dimension]) - Array(previous[dimension])
        additions.concat(added.map { |item| "+#{dimension.singularize}: #{item}" })
      end
      additions << "+keybindings" if current["keybindings"] && !previous["keybindings"]
      additions << "+dynamic_exec (non-literal process commands)" if current["dynamic_exec"] && !previous["dynamic_exec"]
      additions
    end

    SHELL_NOISE = [
      "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac",
      "function", "return", "exit", "echo", "printf", "local", "export", "set", "read",
      "shift", "cd", "test", "true", "false", "source", ".", "[", "[[", "]]", "{", "}", "#"
    ].freeze

    private

    def binary_name(command)
      command.to_s.strip.split(/\s+/).first.to_s.split("/").last.to_s
    end
  end
end
