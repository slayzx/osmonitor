require 'config'

class RoadManager
  attr_accessor :conn

  def initialize(conn)
    self.conn = conn
  end

  def load_road(ref_prefix, ref_number)
    road = Road.new(ref_prefix, ref_number)

    fill_road_relation(road)
    
    if road.relation
      data = load_relation_ways(road)
      road.create_relation_graph(data)
    end

    road.relation_comps.each {|c| c.end_nodes.each {|node| node.x, node.y = get_node_xy(node.id)}}

    #data = load_ref_ways(road)
    #road.create_ref_graph(data)

    return road
  end

  def process_tags(row, field_name = 'tags')
    row[field_name] = eval("{#{row[field_name]}}")
    return row
  end

  def fill_road_relation(road)
    sql_select = "SELECT *, OSM_GetRelationLength(r.id) AS length, OSM_IsMostlyCoveredBy(936128, r.id) AS covered
  FROM relations r
  WHERE
    r.tags -> 'type' = 'route' AND
    r.tags -> 'route' = 'road' AND"

    query = sql_select + eval($sql_where_by_road_type[road.ref_prefix], binding()) + " ORDER BY covered DESC, r.id"
    result = @conn.query(query).collect {|row| process_tags(row)}
    road.relation = result[0] if result.size > 0 and result[0]['covered'] == 't'
    road.other_relations = result[1..-1].select {|r| r['covered'] == 't'} if result.size > 1
  end

  def load_relation_ways(road)
    before = Time.now

    sql = "(
  SELECT
    rm.relation_id AS relation_id,
    rm.member_role AS member_role,
    wn.way_id AS way_id,
    w.tags AS way_tags,
    ST_AsText(w.linestring) AS way_geom,
    --ST_Length(w.linestring::geography) AS way_length,
    wn.node_id AS node_id
  --  n.tags AS node_tags,
  --  wn.sequence_id AS node_sequence_id
  FROM way_nodes wn
  INNER JOIN relation_members rm ON (rm.member_id = way_id AND rm.relation_id = #{road.relation['id']})
  INNER JOIN ways w ON (w.id = wn.way_id)
  --INNER JOIN nodes n ON (n.id = wn.node_id)
  ORDER BY rm.sequence_id, wn.way_id, wn.sequence_id
  )"

    result = @conn.query(sql).collect do |row|
      # This simply translates "tags" columns to Ruby hashes.
      process_tags(row, 'way_tags')
      process_tags(row, 'node_tags')
    end

    #@log.debug("   load_road_graph: query took #{Time.now - before}")

    return result
  end

  def load_ref_ways(road)
    before = Time.now
    sql_where = eval($sql_where_by_road_type[road.ref_prefix], binding())

    if !road.relation
      sql = "
  SELECT
    NULL AS relation_id,
    NULL AS member_role,
    wn.way_id AS way_id,
    r.tags AS way_tags,
    ST_AsText(r.linestring) AS way_geom,
    wn.node_id AS node_id
  FROM way_nodes wn "
    else
      sql = "
  SELECT
    rm.relation_id AS relation_id,
    rm.member_role AS member_role,
    wn.way_id AS way_id,
    r.tags AS way_tags,
    ST_AsText(r.linestring) AS way_geom,
    wn.node_id AS node_id
  FROM way_nodes wn 
  LEFT JOIN relation_members rm ON (rm.member_id = way_id AND rm.relation_id = #{road.relation['id']}) "
    end
puts sql_where
    sql += "
  INNER JOIN ways r ON (r.id = wn.way_id)
  WHERE #{sql_where} AND
  (SELECT ST_Contains((SELECT hull FROM relation_boundaries WHERE relation_id = 936128), r.linestring)) = True
  "

    result = @conn.query(sql).collect do |row|
      # This simply translates "tags" columns to Ruby hashes.
      process_tags(row, 'way_tags')
      process_tags(row, 'node_tags')
    end

    #@log.debug("   load_road_graph: query took #{Time.now - before}")

    return result
  end

  def get_node_xy(node_id)
    result = @conn.query("SELECT ST_X(geom), ST_Y(geom) FROM nodes WHERE id = #{node_id}")
    return result.getvalue(0, 0), result.getvalue(0, 1)
  end
end