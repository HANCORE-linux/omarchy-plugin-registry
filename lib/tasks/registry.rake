namespace :registry do
  desc "Grant admin to an account (the supported bootstrap for a fresh deployment)"
  task :grant_admin, [ :email ] => :environment do |_t, args|
    abort "usage: rails registry:grant_admin[you@example.com]" if args[:email].blank?
    user = User.find_or_create_by!(email_address: args[:email].strip.downcase)
    user.update!(admin: true)
    # Not public: the transparency log must not disclose admin login emails
    AuditEvent.record!(action: "user.grant_admin", subject: user)
    puts "#{user.email_address} is an admin. They must sign in and enroll a second factor before admin actions work."
  end

  desc "Seed plugins from a catalog JSON file (array of {publisher, name, summary, repository})"
  task :seed_catalog, [ :path ] => :environment do |_t, args|
    abort "usage: rails registry:seed_catalog[path/to/catalog.json]" if args[:path].blank?
    entries = JSON.parse(File.read(args[:path]))
    results = Registry::SeedCatalog.import(entries)
    results.each do |result|
      entry = result[:entry]
      puts "#{entry['publisher']}/#{entry['name']}: #{result[:status]}#{" — #{result[:reason]}" if result[:reason]}"
    end
    puts "Run pending review jobs (bin/jobs) or rails registry:process_reviews to complete the pipeline."
  end

  desc "Run any pending review jobs inline (useful right after seeding)"
  task process_reviews: :environment do
    PluginVersion.processing.find_each do |version|
      Registry::ReviewJob.perform_now(version)
      puts "#{version.plugin.full_name}@#{version.version}: #{version.reload.state}"
    end
    DataPlane::RegenerateJob.perform_later
    puts "Data-plane regeneration queued."
  end

  desc "Import page-view counts from edge analytics (JSONL: {publisher,name,count})"
  task :import_view_counts, [ :path ] => :environment do |_t, args|
    abort "usage: rails registry:import_view_counts[views.jsonl]" if args[:path].blank?
    File.foreach(args[:path]) do |line|
      entry = JSON.parse(line) rescue next
      plugin = Plugin.joins(:publisher).find_by(publishers: { name: entry["publisher"] }, name: entry["name"])
      plugin&.update_columns(views_count: plugin.views_count + entry["count"].to_i)
    end
    puts "View counts imported."
  end

  desc "Import + enforce a signed revocations.json from ANY surviving copy (CDN cache, object storage, a client mirror) after a restore"
  task :import_revocations, [ :path ] => :environment do |_t, args|
    abort "usage: rails registry:import_revocations[revocations.json] (with its .sig alongside)" if args[:path].blank?
    content = File.read(args[:path])
    signature_path = "#{args[:path]}.sig"
    abort "#{signature_path} missing — only SIGNED kill lists can be imported" unless File.exist?(signature_path)
    abort "signature verification failed" unless DataPlane::Signer.verify?(content, File.read(signature_path))

    generator = DataPlane::Regenerate.new
    generator.import_revocation_entries(JSON.parse(content).fetch("revocations", []))
    DataPlane::RegenerateJob.perform_later
    puts "Revocations imported and enforced; regeneration queued."
  end

  desc "Regenerate the entire static data plane (queued — respects the single-regenerator lock)"
  task regenerate: :environment do
    DataPlane::RegenerateJob.perform_later
    puts "Regeneration queued (bin/jobs must be running); output: #{DataPlane.root}"
  end

  desc "Rewrite encrypted secrets under the CURRENT key (run after rotating SECRET_KEY_BASE, before dropping OLD_SECRET_KEY_BASE)"
  task reencrypt_secrets: :environment do
    count = 0
    User.where.not(otp_secret: nil).find_each do |user|
      # Rails' official re-encryption path: decrypts (previous keys allowed),
      # re-encrypts under the current primary
      user.encrypt
      count += 1
    end
    puts "Re-encrypted #{count} TOTP seeds under the current primary key."
  end

  desc <<~DESC
    Import download counts from CDN log aggregation (the production counting
    path). Input: JSONL, one {"publisher","name","version","count","date"} per
    line — produce it from your CDN's logs for GET /dl/... with status 200.
  DESC
  task :import_download_counts, [ :path ] => :environment do |_t, args|
    abort "usage: rails registry:import_download_counts[counts.jsonl]" if args[:path].blank?
    imported = skipped = 0
    File.foreach(args[:path]) do |line|
      entry = JSON.parse(line) rescue next
      version = PluginVersion.joins(plugin: :publisher).find_by(
        publishers: { name: entry["publisher"] }, plugins: { name: entry["name"] },
        version: entry["version"])
      next skipped += 1 if version.nil? || entry["count"].to_i <= 0

      date = Date.parse(entry["date"]) rescue Date.current
      DailyDownload.upsert(
        { plugin_version_id: version.id, date: date, count: entry["count"].to_i },
        unique_by: [ :plugin_version_id, :date ],
        on_duplicate: Arel.sql("count = excluded.count"))
      imported += 1
    end
    # Refresh the cached rollups from the ledger
    PluginVersion.find_each do |version|
      version.update_columns(downloads_count: version.daily_downloads.sum(:count))
    end
    Plugin.find_each do |plugin|
      plugin.update_columns(downloads_count: plugin.versions.sum(:downloads_count))
    end
    DataPlane::RegenerateJob.perform_later
    puts "Imported #{imported} rows (#{skipped} skipped); rollups refreshed, regeneration queued."
  end
end
