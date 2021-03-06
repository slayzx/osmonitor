# encoding: utf-8

require 'config'
require 'unicode_utils'

module OSMonitor
module AdminReport

class AdminManager
  include OSMonitorLogger

  attr_accessor :conn

  def initialize(conn)
    self.conn = conn
    self.conn.query('set enable_seqscan = false;') if conn
  end

  def load_boundary(country, input, all_input)
    boundary = Boundary.new(country, input)

    log_time ' load_relations' do load_relations(boundary, all_input) end
    log_time ' load_ways' do load_ways(boundary) if boundary.relation end

    boundary
  end

  def load_relations(boundary, all_input)
    relations = []

    relations += load_relations_by_id(boundary)
    relations += load_relations_by_config(boundary)

    return if relations.empty?

    boundary.relation = relations[0]

    # Check if the relation is not already reserved for some other id
    # See also https://github.com/ppawel/osmonitor/issues/33
    if boundary.relation.tags['teryt:terc'] != boundary.input['id'] and
        all_input.detect {|row| row['id'] == boundary.relation.tags['teryt:terc'] and row['id'] != boundary.input['id']}
      boundary.relation = relations[1]
    end
  end

  def load_relations_by_config(boundary)
    load_relations_with_sql(eval(OSMonitor.config['admin_report']['find_relation_sql_where_clause']['PL'][boundary.input['admin_level']]))
  end

  def load_relations_by_id(boundary)
    load_relations_with_sql("r.tags @> 'teryt:terc=>#{boundary.input['id']}'::hstore")
  end

  def load_relations_with_sql(where_clause)
    sql = get_relation_sql(where_clause)
    @conn.query(sql).collect {|row| Relation.new(process_tags(row))}
  end

  def load_ways(boundary)
    sql = "SELECT *, ST_AsBinary(w.linestring)
    FROM ways w
    INNER JOIN relation_members rm ON (rm.member_id = w.id)
    WHERE rm.relation_id = #{boundary.relation.id} AND rm.member_type = 'W'"

    @conn.query(sql).each do |row|
      process_tags(row)
      boundary.ways << Way.new(row['id'].to_i, row['member_role'], row['tags'], row['way_wkb'])
    end

    # Check if ways form a closed line.

    sql = "SELECT
      ST_IsClosed(ST_LineMerge(ST_Collect(w.linestring)))
    FROM ways w
    INNER JOIN relation_members rm ON (rm.member_id = w.id)
    WHERE rm.relation_id = #{boundary.relation.id} AND rm.member_type = 'W'"

    boundary.closed = @conn.query(sql).getvalue(0, 0) == 't'
  end

  def get_relation_sql(where_clause)
    "SELECT
    r.id AS id,
    r.tags AS tags,
    r.user_id AS last_update_user_id,
    u.name AS last_update_user_name,
    r.tstamp AS last_update_timestamp,
    r.changeset_id AS last_update_changeset_id
    FROM relations r
    INNER JOIN users u ON (u.id = r.user_id)
    WHERE r.tags @> 'boundary=>administrative'::hstore AND #{where_clause}
    ORDER BY r.id"
  end

  def process_tags(row, field_name = 'tags')
    row[field_name] = eval("{#{row[field_name]}}")
    row
  end
end

end
end
