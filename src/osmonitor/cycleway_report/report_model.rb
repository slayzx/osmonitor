module OSMonitor
module CyclewayReport

class RoadStatus
  attr_accessor :road
  attr_accessor :issues
  attr_accessor :noreport

  def initialize(road)
    self.road = road
    self.issues = []
    self.noreport = false
  end

  def add_error(name, data = {})
    issues << RoadIssue.new(:ERROR, name, data)
  end

  def add_warning(name, data = {})
    issues << RoadIssue.new(:WARNING, name, data)
  end

  def add_info(name, data = {})
    issues << RoadIssue.new(:INFO, name, data)
  end

  def get_issues(type)
    issues.select {|issue| issue.type == type}
  end

  def has_issue_by_name?(name)
    issues.select {|issue| issue.name == name}.size > 0
  end

  def connected?
    road.num_logical_comps == road.correct_num_comps
  end

  def too_many_end_nodes
    road.comps.collect {|comp| comp.end_nodes if comp.end_nodes.size > 4}.select {|x| x}
  end

  def too_few_end_nodes
    road.comps.collect {|comp| comp.end_nodes if comp.end_nodes.size < 2}.select {|x| x}
  end

  def input_length
    road.relation.distance if road.relation
  end

  def found_beginning_and_end?
    road.comps.detect {|comp| !comp.found_beginning_and_end?}.nil?
  end

  def validate
    if road.relation and !road.relation.tags['osmonitor:noreport'].nil?
      @noreport = true
      add_info('noreport')
      return
    end

    if input_length
      add_info('osm_length')
    else
      # No input length = warning.
      add_warning('osm_length')
    end

    add_info('last_update')

    add_error('no_relation') if !road.relation
    add_error('has_many_covered_relations') if road.relation and has_many_covered_relations

    if !ways_without_highway_tag.empty?
      add_error('has_ways_without_highway_tag', {:ways => ways_without_highway_tag})
    end

    if road.empty?
      add_error('empty')
    else
      if !connected?
        add_error('road_disconnected')
      else
        add_error('no_beginning_and_end') if !found_beginning_and_end?
        add_warning('wrong_length') if road.length and input_length and !has_proper_length
        add_error('not_navigable') if found_beginning_and_end? and road.length.nil?#road.has_incomplete_paths?
      end
    end

    add_warning('wrong_network') if road.relation and !has_proper_network

=begin
    #if !road.ways_with_wrong_ref.empty?
    #  add_error('ways_with_wrong_ref', {:ways => road.ways_with_wrong_ref})
    #end

    #add_warning('ways_not_in_relation', {:ways => road.ways}) if road.ways.size > 0
=end
  end

  def green?
    get_issues(:ERROR).empty? and get_issues(:WARNING).empty? and !@noreport
  end

  def length_diff
    return (road.length - road.relation.distance).abs.to_i
  end

  def has_proper_length
    return nil if !road.relation or !road.length or !road.relation.distance
    return length_diff < 2
  end

  def get_network
    road.relation.tags['network'] if road.relation.tags['network']
  end

  def get_proper_network
    return get_relation_network(road.country, road.ref_prefix)
  end

  def has_proper_network
    get_proper_network.nil? or (get_network == get_proper_network)
  end

  def has_many_relations
    return !road.other_relations.empty?
  end

  def has_many_covered_relations
    !road.other_relations.empty?
  end

  def percent_with_lanes
    return (road.ways.values.select { |way| way.tags.has_key?('lanes') }.size / road.ways.size.to_f) * 100
  end

  def percent_with_maxspeed
    return (road.ways.values.select { |way| way.tags.has_key?('maxspeed') }.size / road.ways.size.to_f) * 100
  end

  # Finds ways without "highway" tag (exception is ferry ways, see http://www.openstreetmap.org/browse/way/23541424).
  def ways_without_highway_tag
    return road.ways.values.select { |way| !way.tags.has_key?('highway') and (!way.tags.has_key?('route') or way.tags['route'] != 'ferry') }
  end

  # Finds ways without "ref" tag or with wrong tag value.
  def ways_with_wrong_ref
    return road.ways.values.select {|way| !way.tags.has_key?('ref') or
      !road.get_refs(way).include?(eval($road_type_ref_tag[road.country][road.ref_prefix], binding()))}
  end
end

class RoadIssue
  attr_accessor :name
  attr_accessor :type
  attr_accessor :data

  def initialize(type, name, data)
    self.type = type
    self.name = name
    self.data = data
  end

  def to_s
    "RoadIssue(#{type}, #{name})"
  end
end

class RoadReport < OSMonitor::RoadReport::RoadReport
end

end
end
