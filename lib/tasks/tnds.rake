require File.dirname(__FILE__) +  '/data_loader'

namespace :tnds do

  def operators_from_info(short_name, license_name, trading_name, verbose)
    query_conditions = [ 'lower(name) = ?', 'lower(name) like ?', 'lower(short_name) = ?']
    params = [ short_name.downcase, "#{short_name}%".downcase, short_name.downcase ]
    if license_name
      query_conditions << 'lower(vosa_license_name) = ?'
      params << license_name.downcase
    end
    if trading_name
      query_conditions << 'lower(name) = ?'
      params << trading_name.downcase
    end
    query = query_conditions.join(" OR ")
    conditions =  [query] + params
    operators = Operator.find(:all, :conditions => conditions)
    puts "Loose query found #{operators.size} #{operators.inspect}" if verbose
    # if loose query is ambiguous, try without short name
    query_conditions = []
    params = []
    if (operators.size > 1) && (license_name || trading_name)
      puts "Trying stricter" if verbose
      if license_name
        query_conditions << 'lower(vosa_license_name) = ?'
        params << license_name.downcase
      end
      if trading_name
        query_conditions << 'lower(name) = ?'
        params << trading_name.downcase
      end

      query = query_conditions.join(" OR ")
      conditions =  [query] + params
      operators = Operator.find(:all, :conditions => conditions)
      puts "Strict query found #{operators.size} operators" if verbose
    end
    operators
  end

  namespace :preload do

    desc 'Loads data from a file produced by tnds:preload:unmatched_operators and loads missing
          operator codes and operators into the database. Accepts a file as FILE=file.
          Verbose flag set by VERBOSE=1. Runs in dryrun mode unless DRYRUN=0 is specified'
    task :load_unmatched_operators => :environment do
      tsv_options = { :quote_char => '"',
                      :col_sep => "\t",
                      :row_sep =>:auto,
                      :return_headers => false,
                      :headers => :first_row,
                      :encoding => 'N' }
      check_for_file
      verbose = check_verbose
      dryrun = check_dryrun
      tsv_data = File.read(ENV['FILE'])
      new_data = {}
      outfile = File.open("data/operators/missing_#{Time.now.to_date.to_s(:db)}_with_fixes.tsv", 'w')
      headers = ['Short name',
                 'Trading name',
                 'Name on license',
                 'Code',
                 'Problem',
                 'Region',
                 'File',
                 'Suggested NOC match',
                 'Suggested NOC match name',
                 'Suggested NOC action']
      outfile.write(headers.join("\t")+"\n")
      manual_matches = { 'First in Greater Manchester' => 'First Manchester',
                         'Grovesnor Coaches' => 'Grosvenor Coaches',
                         'TC Minicoaches' => 'T C Minicoaches',
                         'Fletchers Coaches' => "Fletcher's Coaches",
                         'Select Bus & Coach Servi' => 'Select Bus & Coach',
                         'Landmark Coaches' => 'Landmark  Coaches',
                         'Romney Hythe and Dymchu' => 'Romney Hythe & Dymchurch Light Railway',
                         'Sovereign Coaches' => 'Sovereign',
                         'TM Travel' => 'T M Travel Ltd',
                         'First in London' => 'First (in the London area)',
                         'First in Berkshire & Th' => 'First (in the Thames Valley)',
                         'First in Calderdale & H' => 'First Huddersfield',
                         'First in Essex' => 'First (in the Essex area)',
                         'First in Greater Manche' => 'First Manchester',
                         'First in Suffolk & Norf' => 'First Eastern Counties',
                         'Yourbus' => 'Your Bus',
                         'Andybus &amp; Coach' => 'Andybus & Coach Ltd',
                         'AJ & NM Carr' => 'A J & N M Carr',
                         'AP Travel' => 'AP Travel Ltd',
                         'Ad&apos;Rains Psv' => "AD'RAINS PSV",
                         'Anitas Coaches' => "Anita's Coaches",
                         'B&NES' => 'Bath & North East Somerset Council',
                         'Bath Bus Company' => 'Bath Bus Co Ltd',
                         'Briggs Coach Hire' => 'Briggs Coaches',
                         'Centrebus (Beds Herts &' => 'Centrebus (Beds & Herts area)',
                         'Eagles Coaches' => 'Eagle Coaches',
                         'First in Bristol, Bath & the West' => 'First in Bristol',
                         'Green Line (operated by Arriva the Shires)' => 'Green Line (operated by Arriva the Shires & Essex)',
                         'Green Line (operated by First in Berkshire)' => 'Green Line (operated by First - Thames Valley)',
                         'H.C.Chambers & Son' => 'H C Chambers & Son',
                         'Holloways Coaches' => 'Holloway Coaches',
                         'Kimes Coaches' => 'Kimes',
                         'P&O Ferries' => 'P & O Ferries',
                         'RH Transport' => 'R H Transport',
                         "Safford's Coaches" => 'Safford Coaches',
                         }
      FasterCSV.parse(tsv_data, tsv_options) do |row|
        region = row['Region']
        operator_code = row['Code']
        short_name = row['Short name']
        trading_name = row['Trading name']
        license_name = row['Name on license']
        problem = row['Problem']
        file = row['File']

        raise "No short name in line #{row.inspect}" if short_name.blank?
        short_name.strip!
        trading_name.strip! if trading_name
        license_name.strip! if license_name

        operator_info = { :short_name => short_name,
                          :trading_name => trading_name,
                          :license_name => license_name }
        if !new_data[operator_info]
          puts "Looking for #{short_name} #{trading_name} #{license_name}" if verbose
          if manual_name = (manual_matches[short_name] || manual_matches[trading_name])
            operators = Operator.find(:all, :conditions => ['lower(name) = ?', manual_name.downcase])
          else
            operators = operators_from_info(short_name, license_name, trading_name, verbose)
            if operators.empty?
              short_name_canonical = short_name.gsub('First in', 'First')
              short_name_canonical = short_name_canonical.gsub('.', '')
              short_name_canonical = short_name_canonical.gsub('Stagecoach', 'Stagecoach in')
              short_name_canonical = short_name_canonical.gsub('&amp;', '&')
              if short_name_canonical != short_name
                operators = Operator.find(:all, :conditions => ['lower(name) = ?', short_name_canonical.downcase])
              end
             end
          end
          if operators.size == 1
            # puts "Found operator #{operators.first.name} for #{short_name}"
            operator_info[:match] = operators.first
          end


          new_data[operator_info] = {}
        end
        if !new_data[operator_info][region]
          new_data[operator_info][region] = []
        end
        new_data[operator_info][region] << operator_code unless new_data[operator_info][region].include?(operator_code)
        matched_code = operator_info[:match].nil? ? '' : operator_info[:match].noc_code
        matched_name = operator_info[:match].nil? ? '' : operator_info[:match].name
        if matched_code.blank?
          suggested_noc_action = 'New NOC record needed'
        else
          suggested_noc_action = "Add code in region for NOC match"
        end
        outfile.write([short_name,
                       trading_name,
                       license_name,
                       operator_code,
                       problem,
                       region,
                       file,
                       matched_code,
                       matched_name,
                       suggested_noc_action].join("\t")+"\n")
      end
      outfile.close()
      existing_operators = 0
      new_operators = 0
      new_operator_names = []
      new_data.each do |operator_info, region_data|
        if operator_info[:match]
          existing_operators += 1
          operator = operator_info[:match]
        else
          operator = Operator.new( :short_name => operator_info[:short_name])
          if !operator_info[:trading_name].blank?
            operator.name = operator_info[:trading_name]
          end
          if !operator_info[:license_name].blank?
            operator.vosa_license_name = operator_info[:license_name]
          end
          new_operator_names << "#{operator.short_name} #{operator.name} #{operator.vosa_license_name}"
          new_operators += 1
        end
        region_data.each do |region_name, operator_codes|
          region = Region.find_by_name(region_name)
          raise "No region found for name #{region_name}" unless region
          operator_codes.each do |operator_code|
            operator.operator_codes.build(:region => region, :code => operator_code )
            # puts "#{region_name} #{operator_code}"
          end
        end
        if !dryrun
          operator.save!
        end
      end
      puts "New operators: #{new_operators}"
      puts "Existing operators: #{existing_operators}"
      new_operator_names.sort!
      new_operator_names.each do |new_name|
        puts new_name if verbose
      end
    end

    desc 'Produce a list of unmatched operator information from a set of TransXchange
          files in a directory passed as DIR=dir. Verbose flag set by VERBOSE=1.
          To re-load routes from files that have already been loaded in this data generation,
          supply SKIP_LOADED=0. Otherwise these files will be ignored.
          Specify FIND_REGION_BY=directory if regions need to be inferred from directories.'
    task :unmatched_operators => :environment do
      check_for_dir
      verbose = check_verbose
      skip_loaded = true
      skip_loaded = false if ENV['SKIP_LOADED'] == '0'
      if ENV['FIND_REGION_BY'] == 'directory'
        regions_as = :directories
      else
        regions_as = :index
      end
      parser = Parsers::TransxchangeParser.new
      outfile = File.open("data/operators/missing_#{Time.now.to_date.to_s(:db)}.tsv", 'w')
      headers = ['Short name', 'Trading name', 'Name on license', 'Code', 'Problem', 'Region', 'File']
      outfile.write(headers.join("\t")+"\n")
      file_glob = File.join(ENV['DIR'], "**/*.xml")
      index_file = File.join(ENV['DIR'], 'TravelineNationalDataSetFilesList.txt')
      lines = 0
      parser.parse_all_tnds_routes(file_glob, index_file, verbose, skip_loaded, regions_as) do |route|
        if route.route_operators.length != 1
          lines += 1
          row = [route.operator_info[:short_name],
                 route.operator_info[:trading_name],
                 route.operator_info[:name_on_license],
                 route.operator_info[:code],
                 route.route_operators.length > 1 ? 'ambiguous' : 'not found',
                 route.region.name,
                 route.route_sources.first.filename]
          outfile.write(row.join("\t")+"\n")
          if lines % 10 == 0
            outfile.flush
          end
        end
      end
      outfile.close()
    end
  end

  namespace :load do

    desc 'Loads routes from a set of TransXchange files in a directory passed as DIR=dir.
          Runs in dryrun mode unless DRYRUN=0 is specified. Verbose flag set by VERBOSE=1.
          To re-load routes from files that have already been loaded in this data generation,
          supply SKIP_LOADED=0. Otherwise these files will be ignored.
          Specify FIND_REGION_BY=directory if regions need to be inferred from directories.'
    task :routes => :environment do
      check_for_dir
      verbose = check_verbose
      dryrun = check_dryrun
      skip_loaded = true
      skip_loaded = false if ENV['SKIP_LOADED'] == '0'
      puts "Loading routes from #{ENV['DIR']}..."
      if ENV['FIND_REGION_BY'] == 'directory'
        regions_as = :directories
      else
        regions_as = :index
      end
      Route.paper_trail_off
      RouteSegment.paper_trail_off
      RouteOperator.paper_trail_off
      JourneyPattern.paper_trail_off
      parser = Parsers::TransxchangeParser.new
      file_glob = File.join(ENV['DIR'], "**/*.xml")
      index_file = File.join(ENV['DIR'], 'TravelineNationalDataSetFilesList.txt')
      parser.parse_all_tnds_routes(file_glob, index_file, verbose, skip_loaded=false, regions_as) do |route|
        merged = false
        puts "Parsed route #{route.number}" if verbose
        route.route_sources.each do |route_source|
          existing = Route.find(:all, :conditions => ['route_sources.service_code = ?
                                                       AND route_sources.operator_code = ?
                                                       AND route_sources.region_id = ?',
                                                       route_source.service_code,
                                                       route_source.operator_code,
                                                       route_source.region],
                                      :include => :route_sources)
          if existing.size > 1
            raise "More than one existing route for matching source criteria"
          end
          if (!existing.empty?) && (!merged)
            if verbose
              puts "merging with existing route id: #{existing.first.id}, number #{existing.first.number}"
            end
            if !dryrun
              Route.merge_duplicate_route(route, existing.first)
            end
            merged = true
          end
        end
        puts "saving" if verbose
        if (!dryrun) && (!merged)
          route.save!
          puts "saved as #{route.id}" if verbose
        end
      end
      Route.paper_trail_on
      RouteSegment.paper_trail_on
      RouteOperator.paper_trail_on
      JourneyPattern.paper_trail_on
    end

  end

  # Try and identify a route that matches this one in the previous data generation
  def find_previous_for_route(route, verbose, dryrun)
    operators = route.operators.map{ |operator| operator.name }.join(", ")
    puts "Route id: #{route.id}, number: #{route.number}, operators: #{operators}" if verbose
    # Call these functions on the route to make sure stops and stop areas are queried
    # before we enter the find_all_by_number_and_common_stop method, which is scoped to
    # the previous data generation
    route.stop_area_codes
    route.stop_codes

    previous = nil
    FixMyTransport::DataGenerations.in_generation(PREVIOUS_GENERATION) do
      previous = Route.find_existing_routes(route)
    end
    puts "Found #{previous.size} routes" if verbose
    if previous.size > 1
      route_ids = previous.map{ |previous_route| previous_route.id }.join(", ")
      raise "Matched more than one previous route! #{route_ids}"
    end
    previous.each do |previous_route|
      puts "Matched to route id: #{previous_route.id}, number #{previous_route.number}" if verbose
      route.previous_id = previous.first.id
      if ! dryrun
        puts "Saving route" if verbose
        route.save!
      end
    end
  end

  namespace :update do

    desc 'Attempts to match routes in the current generation with routes in the previous
          generation. Call with ROUTE_ID=id to specify a single route to try and match.
          Runs in dryrun mode unless DRYRUN=0 is specified. Verbose flag set by VERBOSE=1'
    task :find_previous_routes => :environment do
      verbose = check_verbose
      dryrun = check_dryrun
      if ENV['ROUTE_ID']
        route = Route.find(ENV['ROUTE_ID'])
        find_previous_for_route(route, verbose, dryrun)
      else
        conditions = { :conditions => ['routes.previous_id IS NULL
                                       AND route_operators.id IS NOT NULL'],
                       :include => :route_operators }
        Route.find_each(conditions) do |route|
          find_previous_for_route(route, verbose, dryrun)
        end
      end
    end

  end

end