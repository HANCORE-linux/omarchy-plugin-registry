module Registry
  # Static extraction of what a plugin *can do*: processes it spawns, hosts it
  # talks to, filesystem reach, keybinding hooks. First release records the
  # fingerprint; an update whose surface GROWS is held for a human (the Flathub
  # model — the only human-review approach that scales).
  class CapabilityFingerprint
    CODE_EXTENSIONS = %w[.qml .js .mjs .sh .bash].freeze

    # Script languages a plugin can carry as sidecar programs (invoked via
    # their interpreter from QML). Without this, a .py helper contributed
    # NOTHING to the fingerprint — its content could change arbitrarily
    # (add exfil, swap a clipboard-fix command) without tripping growth
    # detection. Each such file joins as interpreter process + whole-file
    # digest, same philosophy as non-shell shebang scripts.
    SCRIPT_INTERPRETER_EXTENSIONS = {
      ".py" => "python3", ".rb" => "ruby", ".lua" => "lua", ".pl" => "perl"
    }.freeze

    def self.compute(tarball) = new(tarball).compute

    def initialize(tarball)
      @tarball = tarball
    end

    SHELL_INTERPRETERS = %w[sh bash zsh dash].freeze

    def compute
      processes = Set.new
      hosts = Set.new
      paths = Set.new
      writes = Set.new
      keybindings = false
      dynamic_exec_sites = Set.new
      dynamic_network_sites = Set.new
      shell_digests = Set.new
      dynamic_path_sites = Set.new
      @referenced_tokens = Set.new

      @tarball.contents.each do |path, content|
        ext = File.extname(path).downcase
        shebang = ext.empty? && content.byteslice(0, 2) == "#!"
        # Executable QML smuggled into ANY file (Loader can point at .txt) is
        # still fingerprinted — extension is a hint, not a boundary.
        smuggled_code = !CODE_EXTENSIONS.include?(ext) && !shebang &&
          content.byteslice(0, Registry::TarballInspector::MAX_SCAN_BYTES).to_s
            .match?(/Process\s*\{|command\s*[:=]|bar\.run|execDetached|createQmlObject|
                     import\s+Qt|XMLHttpRequest|\bfetch\s*\(|WebSocket|Loader\s*\{|Qt\./x)
        script_interpreter = SCRIPT_INTERPRETER_EXTENSIONS[ext]
        next unless CODE_EXTENSIONS.include?(ext) || shebang || smuggled_code || script_interpreter
        text = content.dup.force_encoding(Encoding::UTF_8)
        text = text.scrub unless text.valid_encoding?

        # QML/Quickshell process spawns. Every literal command array joins the
        # fingerprint as a whole (argv digest) — swapping ["env","date"] for
        # ["env","sh","-c",…], or any other argv change, is growth. Individual
        # binaries are also recorded, looking through wrapper commands.
        text.scan(/command\s*[:=]\s*\[([^\]]*)\]/m) do |m|
          record_command_array(m[0], processes, dynamic_exec_sites)
        end
        text.scan(/\b(?:bar\.run|execDetached|startDetached)\s*\(\s*\[([^\]]*)\]/m) do |m|
          record_command_array(m[0], processes, dynamic_exec_sites)
        end
        # String-form spawns carry their WHOLE command line in the fingerprint
        # (digest), not just the binary name — editing the arguments of an
        # unchanged `bash -c '...'` string is growth.
        text.scan(/\b(?:bar\.run|execDetached|startDetached)\s*\(\s*["']([^"']+)["']/) do |m|
          processes << binary_name(m[0])
          processes << "cmd:#{Digest::SHA256.hexdigest(m[0]).first(12)}"
          m[0].split(/\s+/).each { |w| @referenced_tokens << w }
        end

        # Opaque execution surfaces are recorded per CALL SITE (digest of the
        # matched snippet), never as a saturating boolean — a second dynamic
        # call, or a change to an existing one, is growth even when the
        # baseline already had one.
        [
          /Qt\.createQmlObject\s*\([^\n]{0,160}/,
          /Qt\.createComponent\s*\(\s*(?!["'])[^\n]{0,160}/,
          /\bsetSource\s*\([^\n]{0,160}/,
          # ANY command binding that isn't a recognized literal array is
          # opaque execution — parens, comments, multiline expressions,
          # function calls, whatever: unrecognized means a human looks
          /command\s*[:=]\s*(?!\[\s*["'])[^\s][^\n]{0,160}/,
          /command\s*[:=]\s*\[\s*["'](?:\/[\w\/]*\/)?(?:#{SHELL_INTERPRETERS.join('|')})["']\s*,\s*["']-c["']\s*,\s*(?!["'])[^\n]{0,160}/,
          /\b(?:bar\.run|execDetached|startDetached)\s*\(\s*(?!["'])(?!\[\s*["'])[^\s][^\n]{0,159}/,
          /\beval\s*\([^\n]{0,160}/,
          /new\s+Function\s*\([^\n]{0,160}/
        ].each do |pattern|
          text.scan(pattern) { |m| dynamic_exec_sites << site_digest(m) }
        end
        # 2. Literal shell -c payloads — the binary name "bash" hides the real
        #    program, so the script itself joins the fingerprint by digest.
        text.scan(/command:\s*\[\s*["'](?:\/[\w\/]*\/)?(#{SHELL_INTERPRETERS.join('|')})["']\s*,\s*["']-c["']\s*,\s*["'](.{0,4000}?)["']\s*\]/m) do |interpreter, script|
          processes << "#{interpreter} -c ##{Digest::SHA256.hexdigest(script).first(8)}"
        end

        # Shell scripts — including extensionless shebang helpers a QML file
        # might invoke by name: the first command of EVERY pipeline segment,
        # commands behind `;`, `&&`, `||`, `|`, control flow, env-var prefixes,
        # and command substitution all join the fingerprint.
        if %w[.sh .bash].include?(ext) || shebang || script_interpreter
          # A script is an opaque program: ANY content change (arguments,
          # URLs, flags — not just command names) is a capability change.
          shell_digests << "#{path}##{Digest::SHA256.hexdigest(content).first(12)}"
          interpreter = shebang ? shebang_interpreter(text) : script_interpreter
          if interpreter && !SHELL_INTERPRETERS.include?(interpreter) && !%w[.sh .bash].include?(ext)
            # The line tokenizer below speaks shell; run over a python3/node
            # daemon it records keywords and variable names as "processes" —
            # noise with no growth value the per-file digest doesn't already
            # provide. Non-shell scripts record what actually runs (their
            # interpreter); literal URLs, paths, and spawn patterns in them
            # are still scanned by the extractors above.
            processes << interpreter
          else
            text.each_line do |line|
              next if line.strip.start_with?("#")
              line.split(/;|&&|\|\||\|/).each do |segment|
                words = segment.strip.split(/\s+/)
                words.each { |w| @referenced_tokens << w }
                word = words.find do |candidate|
                  !SHELL_NOISE.include?(candidate) && candidate.match?(%r{\A[A-Za-z0-9_./-]+\z}) && candidate.exclude?("=")
                end
                processes << binary_name(word) if word
              end
              line.scan(/[$`]\(?\s*([A-Za-z0-9_.\/-]+)/) do |m|
                processes << binary_name(m[0]) unless SHELL_NOISE.include?(m[0])
              end
            end
          end
        end

        # Literal endpoints in ANY supported scheme — http(s) and WebSocket
        # (QML WebSocket url properties, new WebSocket("wss://...")) — are
        # network capability; a new literal endpoint is growth. The authority
        # grammar covers dotted hosts, SINGLE-LABEL hosts (localhost, intranet
        # names), IPv4, and bracketed IPv6 — local-network access is exactly
        # the capability an update must not gain silently.
        text.scan(%r{(?:https?|wss?)://(?:[^@/\s"']*@)?(\[[0-9a-f:.]+\]|[a-z0-9_-]+(?:\.[a-z0-9_-]+)*)}i) do |m|
          hosts << m[0].downcase
        end
        # Network APIs with computed URLs, also per call site
        [
          /\bfetch\s*\(\s*(?!["'])[^\n]{0,160}/,
          /\.open\s*\(\s*["'][A-Z]+["']\s*,\s*(?!["'])[^\n]{0,160}/,
          /new\s+WebSocket\s*\(\s*(?!["'])[^\n]{0,160}/,
          # Concatenation-built URLs: a literal fragment followed by `+`
          # ("https://" + host) is a computed destination, not a literal host
          /\b(?:fetch|WebSocket)\s*\(\s*["'][^"']*["']\s*\+[^\n]{0,160}/,
          /\.open\s*\(\s*["'][A-Z]+["']\s*,\s*["'][^"']*["']\s*\+[^\n]{0,160}/,
          /["'](?:https?|wss?):\/\/[^"']*["']\s*\+[^\n]{0,160}/
        ].each do |pattern|
          text.scan(pattern) { |m| dynamic_network_sites << site_digest(m) }
        end
        # EVERY literal absolute target is filesystem capability — /proc, /sys,
        # /run, /tmp and friends are exactly where secrets and control surfaces
        # live (/proc/self/environ), so no prefix allowlist. file:// URLs are
        # filesystem access dressed as a URL. Conservative overmatch is the
        # point: growth routes to a human.
        text.scan(%r{["'](/(?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]{2,}[^"'\s]*)["']}) { |m| paths << m[0] }
        text.scan(%r{file://(/[^"'\s]+)}i) { |m| paths << m[0] }
        # Filesystem paths BUILT at runtime (env() + concatenation, homePath,
        # StandardPaths, pieces of paths glued with +) are conservatively
        # modeled as dynamic-path sites: static analysis can't see the final
        # target, so changes here always reach a reviewer.
        [
          /\benv\s*\([^\n]{0,120}/,
          /StandardPaths[^\n]{0,120}/,
          /\.homePath\b[^\n]{0,120}/,
          /["'][^"']*\/[^"']*["']\s*\+[^\n]{0,120}/,
          /\+\s*["'][^"']*\/[^"']*["'][^\n]{0,120}/,
          /file:\/\/[^\n]{0,120}/
        ].each do |pattern|
          text.scan(pattern) { |m| dynamic_path_sites << site_digest(m) }
        end
        # Filesystem WRITES are their own dimension: redirections/tee/cp into
        # $HOME are exactly the capability an update must not gain silently.
        text.scan(%r{(?:>>?|\btee\s+(?:-a\s+)?)\s*["']?((?:\$\{?HOME\}?|~)/[^\s"';|&)]+)}) { |m| writes << m[0].delete("{}") }
        keybindings ||= text.match?(/\bShortcut\b|keybinding|GlobalShortcut/i)
      end

      # Any in-tarball file that an invocation references by name is itself
      # executable content: its digest joins the fingerprint, so changing
      # payload.txt behind an unchanged `bash payload.txt` is growth.
      @tarball.files.each do |file_path|
        basename = File.basename(file_path)
        if @referenced_tokens.include?(file_path) || @referenced_tokens.include?(basename) ||
           @referenced_tokens.include?("./#{file_path}")
          shell_digests << "#{file_path}##{Digest::SHA256.hexdigest(@tarball.contents[file_path].to_s).first(12)}"
        end
      end

      {
        "processes" => processes.reject(&:blank?).sort,
        "network" => hosts.sort,
        "paths" => capped(paths.sort, 200),
        "writes" => capped(writes.sort, 200),
        "keybindings" => keybindings,
        "shell_digests" => shell_digests.sort,
        "dynamic_paths" => capped(dynamic_path_sites.sort, 200),
        "dynamic_exec" => dynamic_exec_sites.sort,
        "dynamic_network" => dynamic_network_sites.sort
      }
    end

    # A stable identifier for one opaque call site: whitespace-normalized text
    def site_digest(match)
      text = match.is_a?(Array) ? match.join : match.to_s
      Digest::SHA256.hexdigest(text.gsub(/\s+/, " ").strip).first(12)
    end

    # Wrappers whose real payload is the next argv element
    EXEC_WRAPPERS = %w[env nice nohup timeout stdbuf setsid sudo doas xargs].freeze

    # A command array that mixes literal strings with expressions — e.g.
    # ["env", program, arg] — is dynamic execution: the quoted parts alone
    # must not stand in for the whole argv.
    def record_command_array(raw, processes, dynamic_exec_sites)
      elements = raw.scan(/["']([^"']*)["']/).flatten
      residue = raw.gsub(/["'][^"']*["']/, "").gsub(/[\s,]/, "")
      dynamic_exec_sites << site_digest(raw) if residue.present?
      elements.each { |e| e.split(/\s+/).each { |w| @referenced_tokens << w } }
      record_argv(elements, processes) if elements.any?
    end

    # Record a literal argv: the leading binary (looking through wrappers),
    # every element, and a digest of the whole argv so ANY change — flags,
    # URLs, appended commands — alters the stored fingerprint.
    def record_argv(elements, processes)
      index = 0
      index += 1 while index < elements.length - 1 && EXEC_WRAPPERS.include?(binary_name(elements[index]))
      processes << binary_name(elements[index])
      processes << binary_name(elements[0]) # the wrapper itself, if any
      processes << "argv:#{Digest::SHA256.hexdigest(elements.join("\x00")).first(12)}"
    end

    # Storage stays bounded WITHOUT opening a bypass: past the cap, a digest
    # of the full list joins the fingerprint, so any change in the truncated
    # tail still changes the stored value and trips the growth hold.
    def capped(list, cap)
      return list if list.size <= cap
      list.first(cap) + [ "overflow:#{Digest::SHA256.hexdigest(list.join("\n")).first(12)} (#{list.size} total)" ]
    end

    # An update's fingerprint compared against the last published one.
    # Returns [] when nothing grew; otherwise human-readable additions.
    def self.growth(previous, current)
      return [] if previous.blank?
      additions = []
      %w[processes network paths writes].each do |dimension|
        added = Array(current[dimension]) - Array(previous[dimension])
        additions.concat(added.map { |item| "+#{dimension.singularize}: #{item}" })
      end
      additions << "+keybindings" if current["keybindings"] && !previous["keybindings"]
      %w[shell_digests dynamic_paths dynamic_exec dynamic_network].each do |dimension|
        added = Array(current[dimension]) - Array(previous[dimension])
        # Legacy boolean fingerprints compare as arrays after Array(); a true
        # baseline becomes [true] and any site list differs, forcing one
        # re-review — safe in the conservative direction.
        additions.concat(added.map { |site| "+#{dimension}: #{site}" })
      end
      additions
    end

    SHELL_NOISE = [
      "if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac",
      "function", "return", "exit", "echo", "printf", "local", "export", "set", "read",
      "shift", "cd", "test", "true", "false", "source", ".", "[", "[[", "]]", "{", "}", "#"
    ].freeze

    private

    # "#!/usr/bin/env python3" -> "python3", "#!/bin/bash -e" -> "bash"
    def shebang_interpreter(text)
      line = text.lines.first.to_s
      return nil unless line.start_with?("#!")
      words = line.delete_prefix("#!").strip.split(/\s+/)
      name = binary_name(words[0])
      name = binary_name(words[1]) if name == "env" && words[1]
      name.presence
    end

    def binary_name(command)
      command.to_s.strip.split(/\s+/).first.to_s.split("/").last.to_s
    end
  end
end
