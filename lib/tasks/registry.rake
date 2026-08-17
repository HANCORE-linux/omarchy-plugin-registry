namespace :registry do
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
    DataPlane::Regenerate.all
  end

  desc "Regenerate the entire static data plane"
  task regenerate: :environment do
    DataPlane::Regenerate.all
    puts "Data plane regenerated at #{DataPlane.root}"
  end
end
