ActionController::Routing::Routes.draw do |map|

  map.root :controller => 'home'

  map.resources :places, :controller => 'problems', 
                         :except => [:update, :edit], 
                         :collection => {:choose_location => :get}

  map.resources :routes, :only => [:show], 
                         :collection => {:random => :get}, 
                         :member => {:respond => :get}

  map.resources :stops, :only => [:show], 
                        :collection => {:random => :get}, 
                        :member => {:respond => :get}

  map.resources :stop_areas, :only => [:show], 
                             :collection => {:random => :get}, 
                             :member => {:respond => :get}

  map.namespace :admin do |admin|
    admin.root :controller => 'location_searches'
    admin.resources :location_searches, :only => [:index, :show]
  end
  
end
