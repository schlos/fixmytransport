require 'spec_helper'

describe ApplicationHelper do

  describe 'when creating search links' do

    it 'should create links with URI-encoded search params' do
      helper.external_search_link("some=& string").should == "http://www.google.co.uk/search?ie=UTF-8&q=some%3D%26+string"
    end

  end

  # See config/initializers/strip_tags_xss_patch.rb
  describe 'when using the strip_tags helper' do

    it 'should strip a script tag' do
      assert_equal "", helper.strip_tags("<script>")
    end

    it 'should escape broken HTML' do
      escaped_stripped = ERB::Util.html_escape(helper.strip_tags("something <img onerror=alert(1337)"))
      assert_equal "something &lt;img onerror=alert(1337)", escaped_stripped
    end
  end

  describe 'when using "on the" or "at the" to describe a location' do

    it 'should use "on the" for a route' do
      helper.on_or_at_the(Route.new).should == 'on the'
    end

    it 'should use "at the" for a stop' do
      helper.on_or_at_the(Stop.new).should == 'at the'
    end

    it 'should use "at the" for a stop area' do
      helper.on_or_at_the(StopArea.new).should == 'at the'
    end

  end

  describe 'when returning a problem sending history' do

    before do
      council_contact = mock_model(CouncilContact, :name => 'A test council')
      operator_contact = mock_model(OperatorContact, :name => 'A test operator')
      older_sent_email = mock_model(SentEmail, :created_at => DateTime.parse('2011-09-07'),
                                               :recipient => council_contact)
      other_council_contact = mock_model(CouncilContact, :name => 'another test council')
      other_older_sent_email = mock_model(SentEmail, :created_at => DateTime.parse('2011-09-07'),
                                               :recipient => other_council_contact)
      newer_sent_email = mock_model(SentEmail, :created_at => DateTime.parse('2011-09-08'),
                                               :recipient => operator_contact)
      @problem = mock_model(Problem, :reports_sent => [newer_sent_email, older_sent_email])
      @two_council_problem = mock_model(Problem, :reports_sent => [other_older_sent_email, older_sent_email])
    end

    it 'should return an <li> element containing two reports sent on the same day in one sentence' do
      expected_elements = '<li>Sent to another test council and A test council on 07 Sep 2011</li>'
      helper.problem_sending_history(@two_council_problem).should == expected_elements
    end

    it 'should return an <li> element for each day reports were sent on' do
      expected_elements = '<li>Sent to A test council on 07 Sep 2011</li><li>Sent to A test operator on 08 Sep 2011</li>'
      helper.problem_sending_history(@problem).should == expected_elements
    end

    it 'should return an empty string if there are no reports sent' do
      @problem.stub!(:reports_sent).and_return([])
      helper.problem_sending_history(@problem).should == ''
    end

  end

  describe 'when giving an explanation of reporting a problem at a location' do

    before do
      @station = mock_model(StopArea, :responsible_organizations => [],
                                      :area_type => 'GRLS',
                                      :transport_mode_names => ['Train'])
      operator = mock_model(Operator, :name => 'Ferry Company X')
      council = mock_model(Council, :name => 'Local Authority Y')
      @ferry_terminal = mock_model(StopArea, :responsible_organizations => [operator, council],
                                             :area_type => 'GFTD',
                                             :transport_mode_names => ['Ferry'])
      @train_route = mock_model(TrainRoute, :responsible_organizations => [operator, council])
      @bus_route = mock_model(BusRoute, :responsible_organizations => [])
      @bus_stop = mock_model(Stop, :responsible_organizations => [council],
                                   :transport_mode_names => ['Bus'])
    end

    it 'should return a suitable string for a train station with no responsible organizations' do
      expected_explanation = ['Poor station facilities? Access problems? Report',
                              'a problem at this station'].join(" ")
      helper.location_explanation(@station).should == expected_explanation
    end

    it 'should return a suitable string for a ferry terminal with two responsible organizations' do
      expected_explanation = ['Poor terminal facilities? Access problems? Report a problem',
                              'at this terminal to Ferry Company X or Local Authority Y'].join(" ")
      helper.location_explanation(@ferry_terminal).should == expected_explanation
    end

    it 'should return a suitable string for a bus route with one responsible organisation' do
      expected_explanation = ['Late trains? Fare or ticket problems? Report a problem on',
                              'this route to Ferry Company X or Local Authority Y'].join(" ")
      helper.location_explanation(@train_route).should == expected_explanation
    end

    it 'should return a suitable string for a train route with no responsible organisations' do
      expected_explanation = 'Overcrowding? Late buses? Report a problem on this route'
      helper.location_explanation(@bus_route).should == expected_explanation
    end

    it 'should return a suitable string for a bus stop with one responsible organisation' do
      expected_explanation = ['Broken glass? Missing timetable? Report a problem at this bus',
                              'stop to Local Authority Y'].join(" ")
      helper.location_explanation(@bus_stop).should == expected_explanation
    end

  end

  describe 'when giving an "at_the_location" string' do

    it 'should describe a bus stop as "at the Williams Avenue bus stop"' do
      stop = mock_model(Stop, :name => "Williams Avenue", :transport_mode_names => ['Bus'])
      helper.at_the_location(stop).should == "at the Williams Avenue bus stop"
    end

    it 'should describe a bus route as "on the C10"' do
      route = mock_model(BusRoute, :name => 'C10 bus route')
      helper.at_the_location(route).should == 'on the C10 bus route'
    end

    it 'should describe a train station as "at London Euston Rail Station"' do
      station = mock_model(StopArea, :area_type => 'GRLS',
                                     :name => 'London Euston Rail Station',
                                     :transport_mode_names => ['Train'])
      helper.at_the_location(station).should == 'at London Euston Rail Station'
    end

    it 'should describe a metro station as "at Baker Street Underground Station"' do
      station = mock_model(StopArea, :area_type => 'GTMU',
                                     :name => 'Baker Street Underground Station',
                                     :transport_mode_names => ['Tram/Metro'])
      helper.at_the_location(station).should == 'at Baker Street Underground Station'
    end

    it 'should describe a ferry station as "at Armadale Ferry Terminal"' do
      station = mock_model(StopArea, :area_type => 'GFTD',
                                     :name => 'Armadale Ferry Terminal',
                                     :transport_mode_names => ['Ferry'])
      helper.at_the_location(station).should == 'at Armadale Ferry Terminal'
    end

    it 'should describe a bus station as "at the Sevenoaks Bus Station"' do
      station = mock_model(StopArea, :area_type => 'GBCS', :name => 'Sevenoaks Bus Station')
      helper.at_the_location(station).should == 'at the Sevenoaks Bus Station'
    end

  end

  describe 'when returning the readable location type of a location' do

    it 'should return "bus stop" for a stop' do
      location = mock_model(Stop, :stop_type => 'BCS', :transport_mode_names => ['Bus', 'Coach', 'Tram/Metro'])
      helper.readable_location_type(location).should == 'bus stop'
    end

    it 'should return "bus stop" for a stop' do
      location = mock_model(Stop, :stop_type => 'BCT', :transport_mode_names => ['Bus', 'Coach', 'Tram/Metro'])
      helper.readable_location_type(location).should == 'bus stop'
    end

    it 'should return "route" for a route' do
      helper.readable_location_type(Route.new).should == 'route'
    end

    it 'should return "bus route" for a bus route' do
      helper.readable_location_type(BusRoute.new).should == 'bus route'
    end

    it 'should return "route" for a metro/tram route' do
      helper.readable_location_type(TramMetroRoute.new).should == 'route'
    end

    it 'should return "bus station" for a stop area' do
      location = mock_model(StopArea, :area_type => 'GBCS', :transport_mode_names => ['Bus', 'Coach', 'Tram/Metro'])
      helper.readable_location_type(location).should == 'bus station'
    end

    it 'should return "station" for a train stop' do
      location = mock_model(Stop, :stop_type => 'RLY', :transport_mode_names => ['Train'])
      helper.readable_location_type(location).should == 'station'
    end

    it 'should return "station" for a train stop area' do
      location = mock_model(StopArea, :area_type => 'GRLS', :transport_mode_names => ['Train'])
      helper.readable_location_type(location).should == 'station'
    end

    it 'should return "station" for a metro/tram stop' do
      location = mock_model(Stop, :stop_type => 'TMU', :transport_mode_names => ['Tram/Metro'])
      helper.readable_location_type(location).should == 'station'
    end

    it 'should return "station" for a metro/tram stop area' do
      location = mock_model(StopArea, :area_type => 'GTMU', :transport_mode_names => ['Tram/Metro'])
      helper.readable_location_type(location).should == 'station'
    end

    it 'should return "terminal" for a ferry stop area' do
      location = mock_model(StopArea, :area_type => 'GTFS', :transport_mode_names => ['Ferry'])
      helper.readable_location_type(location).should == 'terminal'
    end



  end

end
