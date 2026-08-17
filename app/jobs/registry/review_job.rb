module Registry
  # The automated review pipeline, run on every version of every plugin —
  # updates never skip it. Deterministic scan -> capability fingerprint ->
  # delta check -> AI review -> hold window -> live.
  class ReviewJob < ApplicationJob
    queue_as :review
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
      # review. The baseline includes yanked and once-published-quarantined
      # versions: a takedown must not erase the baseline and let the next
      # submission inherit a smaller comparison surface.
      fingerprint = CapabilityFingerprint.compute(tarball)
      previous = version.review_baseline
      growth = CapabilityFingerprint.growth(previous&.capability_fingerprint, fingerprint)

      # 3. AI review (escalate-only) — updates carry the file-level diff so the
      # reviewer judges the change, not just the snapshot
      changed_files = changed_files_since(previous, tarball) if AiReview.enabled?
      ai = AiReview.review(version:, tarball:, fingerprint:, scan_findings: findings,
        previous: previous, capability_growth: growth, changed_files: changed_files || [],
        previous_contents: @previous_contents || {})

      # An admin may have rejected or security-held this version while the
      # scan ran — never overwrite a terminal state with a pipeline outcome.
      version.with_lock do
        break unless version.processing?

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
          # First releases have no capability baseline; without the AI leg of
          # the pipeline, someone must look before the first bytes go live.
          quarantine!(version, "first release requires human review while AI review is disabled")
        when (fingerprint["dynamic_exec"].present? || fingerprint["dynamic_network"].present?) &&
             !AiReview.enabled? && !Rails.application.config.x.skip_first_release_gate
          # Static analysis cannot see the VALUES flowing into a dynamic call
          # site — a variable can turn malicious with no textual change at the
          # site. Plugins containing dynamic execution/network therefore never
          # ride pure-deterministic auto-release: every version needs judgment
          # (AI when enabled, a human otherwise). Literal commands avoid this.
          quarantine!(version, "contains dynamic execution/network call sites — requires judgment review on every version")
        else
          hold_or_release(version)
        end
      end
    end

    private

    def changed_files_since(previous, tarball)
      return [] unless previous&.tarball&.attached?
      previous_inspection = TarballInspector.inspect_bytes(previous.tarball.download)
      previous_digests = previous_inspection.digests
      added = tarball.files - previous_digests.keys
      changed = tarball.files.select { |f| previous_digests[f] && previous_digests[f] != tarball.digests[f] }
      removed = previous_digests.keys - tarball.files
      # Bounded previous contents for changed files so the reviewer can diff
      # actual source, not just names
      @previous_contents = changed.first(20).index_with do |f|
        previous_inspection.contents[f].to_s.byteslice(0, 16.kilobytes).dup.force_encoding(Encoding::UTF_8).scrub
      end
      added.map { |f| "+#{f}" } + changed.map { |f| "~#{f}" } + removed.map { |f| "-#{f}" }
    rescue TarballInspector::InvalidTarball
      []
    end

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
      # SEEDED plugins whose only history is rejection revert to a visible
      # placeholder (the directory promised the catalog entry exists and is
      # uninstallable). Ordinary rejected-only submissions stay active but
      # simply drop out of directory_visible — a failed first attempt is not
      # a public listing.
      plugin = version.plugin
      seeded = !plugin.publisher.claimed? ||
        plugin.versions.joins(:user).exists?(users: { system: true })
      if seeded && plugin.active? && plugin.versions.where.not(state: :rejected).none?
        plugin.update!(state: :quarantined)
      end
    end

    def quarantine!(version, reason)
      version.update!(state: :quarantined, review_notes: reason)
      AuditEvent.record!(action: "version.auto_quarantine", subject: version,
        metadata: { plugin: version.plugin.full_name, version: version.version, reason: reason })
    end
  end
end
