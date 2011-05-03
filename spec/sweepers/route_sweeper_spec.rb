require 'spec_helper'

describe RouteSweeper do
 
  describe 'when expiring cached files for a route' do 

    it "should expire the main url for that route's region" do
      mock_region = mock_model(Region)
      mock_route = mock_model(Route, :region => mock_region, 
                                     :previous_version => nil)
      route_sweeper = RouteSweeper.instance
      route_sweeper.controller = mock('controller', 
                                      :url_for => '/routes/east-anglia', 
                                      :main_url => 'localhost:3000/routes/east-anglia')
      route_sweeper.should_receive(:expire_fragment).with("localhost:3000/routes/east-anglia")
      route_sweeper.after_update(mock_route)
    end

  end
end