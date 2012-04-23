namespace :update do

  desc 'Load a new generation of transport data. Will run in dryrun mode unless DRYRUN=0 is specified.
        Sepcify verbose output with VERBOSE=1.'
  task :all => :environment do

    Rake::Task['update:create_data_generation'].execute

    # Load NPTG data
    Rake::Task['update:nptg'].execute
    
    # LOAD NAPTAN DATA
    Rake::Task['update:naptan'].execute

    # LOAD NOC DATA
    Rake::Task['update:noc'].execute

    # LOAD TNDS DATA

    # Rake::Task['naptan:post_load:mark_metro_stops'].execute
   
  end

  desc "Create a new data generation."
  task :create_data_generation => :environment do
    dryrun = check_dryrun()
    puts "Creating a new data generation..."

    check_new_generation()
    data_generation = DataGeneration.new(:name => 'Data Update',
                                         :description => 'Update from official data sources',
                                         :id => CURRENT_GENERATION)
    if !dryrun
      data_generation.save!
      # update the slugs for all non-generation models to be visible in the new
      # data generation
      data_generation_models_with_slugs = [ 'AdminArea',
                                            'Locality',
                                            'Route',
                                            'Region',
                                            'Stop',
                                            'StopArea',
                                            'Operator' ]
      conn = Slug.connection
      data_generation_models = data_generation_models_with_slugs.map{ |model| conn.quote(model) }.join(",")
      conn.execute("UPDATE slugs
                    SET generation_high = #{data_generation.id}
                    WHERE sluggable_type
                    NOT in (#{data_generation_models})")
    end
  end

  desc "Update NPTG data to the current data generation. Runs in dryrun mode unless DRYRUN=0
        is specified. Verbose flag set by VERBOSE=1."
  task :nptg => :environment do
    ENV['GENERATION'] = CURRENT_GENERATION.to_s
    ENV['FILE'] = File.join(MySociety::Config.get('NPTG_DIR', ''), 'Regions.csv')
    puts "calling regions"
    Rake::Task['nptg:update:regions'].execute
    puts "called regions"
    ENV['FILE'] = File.join(MySociety::Config.get('NPTG_DIR', ''), 'AdminAreas.csv')
    Rake::Task['nptg:update:admin_areas'].execute
    ENV['FILE'] = File.join(MySociety::Config.get('NPTG_DIR', ''), 'Districts.csv')
    Rake::Task['nptg:update:districts'].execute
    ENV['FILE'] = File.join(MySociety::Config.get('NPTG_DIR', ''), 'Localities.csv')
    Rake::Task['nptg:update:localities'].execute
    ENV['MODEL'] = 'Locality'
    # N.B. Run this before loading stops or stop areas so that the scoping of those slugs doesn't
    # get out of sync with the rejigged locality slugs
    Rake::Task['update:normalize_slug_sequences'].execute
    Rake::Task['nptg:geo:convert_localities'].execute

    # Can just reuse the load code here - localities will be scoped by the current data generation
    ENV['FILE'] = File.join(MySociety::Config.get('NPTG_DIR', ''), 'LocalityHierarchy.csv')
    Rake::Task['nptg:load:locality_hierarchy'].execute
  end

  desc 'Update NaPTAN data to the current data generation. Runs in dryrun mode unless DRYRUN=0
        is specified. Verbose flag set by VERBOSE=1'
  task :naptan => :environment do
    ENV['GENERATION'] = CURRENT_GENERATION.to_s
    ENV['FILE'] = File.join(MySociety::Config.get('NAPTAN_DIR', ''), 'Stops.csv')
    Rake::Task['naptan:update:stops'].execute
    Rake::Task['naptan:geo:convert_stops'].execute

    ENV['FILE'] = File.join(MySociety::Config.get('NAPTAN_DIR', ''), 'StopAreas.csv')
    Rake::Task['naptan:update:stop_areas'].execute
    Rake::Task['naptan:geo:convert_stop_areas'].execute

    ENV['FILE'] = File.join(MySociety::Config.get('NAPTAN_DIR', ''), 'StopsInArea.csv')
    Rake::Task['naptan:update:stop_area_memberships'].execute

    # Can just reuse the load code here - stop areas will be scoped by the current data generation
    ENV['FILE'] = File.join(MySociety::Config.get('NAPTAN_DIR', ''), 'AreaHierarchy.csv')
    Rake::Task['naptan:load:stop_area_hierarchy'].execute

    # Some post-load cleanup on NaPTAN data - add locality to stop areas, and any stops missing locality
    Rake::Task['naptan:post_load:add_locality_to_stops'].execute
    Rake::Task['naptan:post_load:add_locality_to_stop_areas'].execute

    # Add some other data - Rail stop codes
    ENV['FILE'] = File.join(MySociety::Config.get('NAPTAN_DIR', ''), 'RailReferences.csv')
    Rake::Task['naptan:post_load:add_stops_codes'].execute

  end

  desc 'Update NOC data to the current data generation. Runs in dryrun mode unless DRYRUN=0
        is specified. Verbose flag set by VERBOSE=1'
  task :noc => :environment do
    ENV['GENERATION'] = CURRENT_GENERATION.to_s
    ENV['FILE'] = File.join(MySociety::Config.get('NOC_DIR', ''), 'NOC_DB.csv')
    Rake::Task['noc:update:operators'].execute
    Rake::Task['noc:update:operator_codes'].execute
    Rake::Task['noc:update:vosa_licenses'].execute
    Rake::Task['noc:update:operator_contacts'].execute
  end


  desc 'Display a list of updates that have been made to instances of a model.
        Default behaviour is to only show updates that have been marked as replayable.
        Specify ALL=1 to see all updates. Specify model class as MODEL=ModelName'
  task :show_updates => :environment do
    check_for_model()
    model = ENV['MODEL'].constantize
    only_replayable = (ENV['ALL'] == "1") ? false : true
    update_hash = get_updates(model, only_replayable=only_replayable, ENV['DATE'])
    update_hash.each do |identity, changes|
      identity_type = identity[:identity_type]
      identity_hash = identity[:identity_hash]
      changes.each do |details_hash|
        id = details_hash[:id]
        event = details_hash[:event]
        date = details_hash[:date]
        changes = details_hash[:changes]
        puts "#{id} #{date} #{event} #{identity_hash.inspect} #{changes.inspect}"
      end
    end
  end

  desc 'Apply the replayable local updates for a model class that is versioned in data generations.
        Runs in dryrun mode unless DRYRUN=0 is specified. Verbose flag set by VERBOSE=1'
  task :replay_updates => :environment do
    check_for_model()
    dryrun = check_dryrun()
    verbose = check_verbose()
    model = ENV['MODEL'].constantize
    replay_updates(model, dryrun, verbose)
  end

  desc 'Reorder any slugs that existed in the previous generation, but have been given a different
        sequence by the arbitrary load order'
  task :normalize_slug_sequences => :environment do
    check_for_model()
    check_for_generation()
    ENV['MODEL'].constantize.normalize_slug_sequences(ENV['GENERATION'].to_i)
  end

end