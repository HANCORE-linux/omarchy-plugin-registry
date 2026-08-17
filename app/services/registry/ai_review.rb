module Registry
  # LLM review of the full source (first publish) or context-rich update, with
  # scan results and the capability fingerprint attached. The verdict can only
  # ESCALATE (flag -> quarantine + admin queue) — it never approves anything and
  # never overrides a deterministic failure, because the known counter-attack is
  # prompt-injecting the scanner.
  #
  # Pluggable: config.x.ai_review_command is a shell command that reads the
  # review request as JSON on stdin and prints {"verdict": "pass"|"flag",
  # "reasons": [...]} on stdout. Unset = review disabled (Phase 2 default-on
  # once an adapter is provisioned).
  class AiReview
    TIMEOUT_SECONDS = 180

    Result = Struct.new(:verdict, :reasons) do
      def flagged? = verdict == "flag"
    end

    def self.enabled? = Rails.application.config.x.ai_review_command.present?

    def self.review(version:, tarball:, fingerprint:, scan_findings:, previous: nil, capability_growth: [], changed_files: [], previous_contents: {})
      return Result.new("pass", [ "ai review disabled" ]) unless enabled?

      payload = {
        plugin: version.plugin.full_name,
        version: version.version,
        manifest: version.manifest,
        fingerprint: fingerprint,
        scan_findings: scan_findings,
        # Update context: what the last reviewed version looked like, so the
        # reviewer judges the CHANGE, not just the snapshot
        previous: previous && { version: previous.version, fingerprint: previous.capability_fingerprint },
        changed_files: changed_files,
        previous_contents: previous_contents,
        capability_growth: capability_growth,
        files: tarball.contents.transform_values { |c| c.dup.force_encoding(Encoding::UTF_8).scrub }
      }

      output = run_command(Rails.application.config.x.ai_review_command, payload.to_json)
      parsed = JSON.parse(output)
      # Only an explicit "pass" passes; anything unrecognized escalates — a
      # broken adapter must not silently wave versions through.
      case parsed["verdict"]
      when "pass" then Result.new("pass", Array(parsed["reasons"]))
      when "flag" then Result.new("flag", Array(parsed["reasons"]))
      else Result.new("flag", [ "unrecognized ai verdict: #{parsed['verdict'].inspect}" ])
      end
    rescue StandardError => e
      # A broken reviewer must not block publishing silently or approve anything:
      # treat errors as a flag so a human looks.
      Result.new("flag", [ "ai review errored: #{e.message.first(200)}" ])
    end

    MAX_OUTPUT_BYTES = 1.megabyte

    # Bounded in time AND output, with the child reliably killed on timeout —
    # stalled adapters must not accumulate as zombie processes. The child runs
    # with a SCRUBBED environment (unsetenv_others): it processes
    # attacker-controlled plugin source and must never see REGISTRY_SIGNING_SEED,
    # SECRET_KEY_BASE, SMTP credentials, or anything else from the app env.
    # Adapters that need API keys read them from their own config files; run
    # them under a separate UID (systemd DynamicUser / a sidecar) for full
    # filesystem isolation — see docs/deploy.md.
    ADAPTER_ENV = lambda do
      { "PATH" => ENV["PATH"], "HOME" => Dir.tmpdir, "LANG" => ENV["LANG"] }.compact
    end

    def self.run_command(command, stdin_data)
      require "open3"
      Open3.popen3(ADAPTER_ENV.call, command, unsetenv_others: true, pgroup: true) do |stdin, stdout, stderr, wait_thread|
        writer = Thread.new do
          stdin.write(stdin_data)
        rescue Errno::EPIPE
          nil
        ensure
          stdin.close rescue nil
        end
        reader = Thread.new { stdout.read(MAX_OUTPUT_BYTES + 1) }
        # Drain-and-discard stderr: it processes unpublished plugin source and
        # must reach neither the app logs nor unbounded memory; draining also
        # keeps a chatty adapter from deadlocking on a full pipe.
        drainer = Thread.new do
          nil while stderr.read(65536)
        rescue IOError
          nil
        end

        unless wait_thread.join(TIMEOUT_SECONDS)
          # Negative pid = the whole process group — shell-spawned descendants
          # die with the parent
          Process.kill("KILL", -wait_thread.pid) rescue Process.kill("KILL", wait_thread.pid) rescue nil
          wait_thread.join(5)
          raise "reviewer timed out after #{TIMEOUT_SECONDS}s"
        end
        writer.join(1)
        drainer.join(1)
        output = reader.value.to_s
        raise "reviewer output exceeds #{MAX_OUTPUT_BYTES} bytes" if output.bytesize > MAX_OUTPUT_BYTES
        raise "reviewer exited #{wait_thread.value.exitstatus}" unless wait_thread.value.success?
        output
      end
    end
  end
end
