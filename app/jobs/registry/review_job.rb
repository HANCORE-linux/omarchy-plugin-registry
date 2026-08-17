module Registry
  # The automated review pipeline, run on every version of every plugin —
  # updates never skip it. Deterministic scan -> capability fingerprint ->
  # delta check -> AI review -> hold window -> live.
  class ReviewJob < ApplicationJob
    queue_as :default
    # One review per plugin at a time: concurrent reviews of back-to-back
    # submissions could both observe the same (or no) capability baseline.
    limits_concurrency to: 1, key: ->(version) { "review_plugin_#{version.plugin_id}" }

    def perform(version)
      return unless version.processing?
      plugin = version.plugin

      tarball = TarballInspector.inspect_bytes(version.tarball.download)

      # 1. Deterministic scanning
      scanner = Scanner.new(tarball, plugin: plugin)
      scanner.scan
      findings = scanner.findings.map(&:as_json)

      # 2. Capability fingerprint + delta vs the last version that CLEARED
      # review (published or waiting out its hold) — comparing only against
      # published versions would let capabilities ratchet up unreviewed through
      # a chain of versions submitted inside one hold window.
      fingerprint = CapabilityFingerprint.compute(tarball)
      previous = plugin.versions.where(state: [ :published, :held ]).where.not(id: version.id)
        .order(version_sort_key: :desc).first
      growth = CapabilityFingerprint.growth(previous&.capability_fingerprint, fingerprint)

      # 3. AI review (escalate-only)
      ai = AiReview.review(version:, tarball:, fingerprint:, scan_findings: findings)

      version.update!(
        capability_fingerprint: fingerprint,
        scan_results: { "findings" => findings, "capability_growth" => growth,
                        "ai" => { "verdict" => ai.verdict, "reasons" => ai.reasons } }
      )

      case
      when scanner.verdict == :fail
        reject!(version, findings)
      when scanner.verdict == :flag
        quarantine!(version, "scanner flagged: #{findings.map { |f| f['rule'] }.uniq.join(', ')}")
      when previous && growth.any?
        quarantine!(version, "capability surface grew: #{growth.join(', ')}")
      when ai.flagged?
        quarantine!(version, "ai review flagged: #{ai.reasons.join('; ').first(300)}")
      when previous.nil? && !AiReview.enabled? && !Rails.application.config.x.skip_first_release_gate
        # First releases have no capability baseline; without the AI leg of the
        # pipeline, someone must look before the first bytes go live.
        quarantine!(version, "first release requires human review while AI review is disabled")
      else
        hold_or_release(version)
      end
    end

    private

    # Even a fully clean version waits out a short hold before going live —
    # worm-speed propagation dies to a cheap delay.
    def hold_or_release(version)
      hold = Rails.application.config.x.publish_hold
      # `held` marks "review passed" — the only pipeline state ReleaseVersion
      # accepts besides an admin-released quarantine.
      version.update!(state: :held, hold_until: hold.to_i.positive? ? hold.from_now : Time.current)
      if hold.to_i.positive?
        ReleaseJob.set(wait_until: version.hold_until).perform_later(version)
      else
        ReleaseVersion.call(version)
      end
    end

    def reject!(version, findings)
      version.update!(state: :rejected,
        review_notes: "auto-rejected: #{findings.select { |f| f['severity'] == 'fail' }.map { |f| f['detail'] }.join('; ').first(500)}")
      AuditEvent.record!(action: "version.auto_reject", subject: version, public: true,
        metadata: { plugin: version.plugin.full_name, version: version.version })
    end

    def quarantine!(version, reason)
      version.update!(state: :quarantined, review_notes: reason)
      AuditEvent.record!(action: "version.auto_quarantine", subject: version,
        metadata: { plugin: version.plugin.full_name, version: version.version, reason: reason })
    end
  end
end
