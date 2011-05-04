# == Schema Information
# Schema version: 20100707152350
#
# Table name: route_operators
#
#  id          :integer         not null, primary key
#  operator_id :integer
#  route_id    :integer
#  created_at  :datetime
#  updated_at  :datetime
#

class RouteOperator < ActiveRecord::Base
  belongs_to :operator
  belongs_to :route
  has_paper_trail
  # virtual attribute used for adding new route operators
  attr_accessor :_add
  before_destroy :check_problems

  def check_problems
    conditions = ['location_type = ? AND location_id = ? AND operator_id = ?', 
                  'Route', self.route_id, self.operator_id]
    problems = Problem.find(:all, :conditions => conditions)
    if !problems.empty?
      raise "Cannot destroy association of route #{self.route.id} with operator #{self.operator.id} - problems need updating"
    end
    return true
  end
  
end
