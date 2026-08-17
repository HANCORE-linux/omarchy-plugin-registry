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

    def self.review(version:, tarball:, fingerprint:, scan_findings:)
      return Result.new("pass", [ "ai review disabled" ]) unless enabled?

      payload = {
        plugin: version.plugin.full_name,
        version: version.version,
        manifest: version.manifest,
        fingerprint: fingerprint,
        scan_findings: scan_findings,
        files: tarball.contents.transform_values { |c| c.dup.force_encoding(Encoding::UTF_8).scrub }
      }

      output = run_command(Rails.application.config.x.ai_review_command, payload.to_json)
      parsed = JSON.parse(output)
      verdict = parsed["verdict"] == "flag" ? "flag" : "pass"
      Result.new(verdict, Array(parsed["reasons"]))
    rescue StandardError => e
      # A broken reviewer must not block publishing silently or approve anything:
      # treat errors as a flag so a human looks.
      Result.new("flag", [ "ai review errored: #{e.message.first(200)}" ])
    end

    def self.run_command(command, stdin_data)
      require "open3"
      output = nil
      Timeout.timeout(TIMEOUT_SECONDS) do
        output, status = Open3.capture2(command, stdin_data: stdin_data)
        raise "reviewer exited #{status.exitstatus}" unless status.success?
      end
      output
    end
  end
end
