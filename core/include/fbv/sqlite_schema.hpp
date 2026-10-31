#pragma once

namespace fbv {

// meta.sqlite schema for format_version 1. See docs/package_format.md.
inline constexpr const char* kSqliteSchema = R"SQL(
CREATE TABLE schema_meta(
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
INSERT INTO schema_meta(key, value) VALUES ('format_version', '1');

CREATE TABLE spatial(
  id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL,
  name TEXT,
  elevation REAL,
  parent_id INTEGER
);

CREATE TABLE types(
  id INTEGER PRIMARY KEY,
  guid TEXT,
  ifc_class TEXT,
  name TEXT,
  predefined_type TEXT
);

CREATE TABLE materials(
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  category TEXT
);

CREATE TABLE material_sets(
  id INTEGER PRIMARY KEY,
  name TEXT
);

CREATE TABLE material_layers(
  set_id INTEGER NOT NULL,
  material_id INTEGER NOT NULL,
  thickness REAL,
  layer_order INTEGER NOT NULL
);

CREATE TABLE elements(
  id INTEGER PRIMARY KEY,
  guid TEXT NOT NULL,
  ifc_class TEXT NOT NULL,
  name TEXT,
  tag TEXT,
  type_id INTEGER,
  storey_id INTEGER,
  parent_id INTEGER,
  material_set_id INTEGER,
  bbox_min_x REAL,
  bbox_min_y REAL,
  bbox_min_z REAL,
  bbox_max_x REAL,
  bbox_max_y REAL,
  bbox_max_z REAL,
  mesh_node INTEGER,
  brep_ref INTEGER,
  color_r REAL,
  color_g REAL,
  color_b REAL
);

CREATE TABLE psets(
  id INTEGER PRIMARY KEY,
  element_id INTEGER,
  type_id INTEGER,
  name TEXT NOT NULL,
  source TEXT NOT NULL
);

CREATE TABLE props(
  id INTEGER PRIMARY KEY,
  pset_id INTEGER NOT NULL,
  name TEXT NOT NULL,
  value_text TEXT,
  value_num REAL,
  unit TEXT,
  data_type TEXT
);

CREATE TABLE quantities(
  id INTEGER PRIMARY KEY,
  element_id INTEGER NOT NULL,
  qset TEXT,
  name TEXT NOT NULL,
  value REAL NOT NULL,
  unit TEXT,
  kind TEXT NOT NULL
);

CREATE TABLE classification(
  id INTEGER PRIMARY KEY,
  element_id INTEGER NOT NULL,
  system TEXT,
  code TEXT,
  title TEXT
);

CREATE TABLE assembly(
  id INTEGER PRIMARY KEY,
  parent_id INTEGER,
  name TEXT,
  instance_transform TEXT,
  color TEXT
);

CREATE TABLE spec_views(
  id INTEGER PRIMARY KEY,
  storey_id INTEGER,
  ifc_class TEXT,
  type_name TEXT,
  material_name TEXT,
  element_count INTEGER NOT NULL,
  quantity_kind TEXT,
  quantity_sum REAL
);

CREATE VIRTUAL TABLE fts_elements USING fts5(
  element_id UNINDEXED,
  name,
  tag,
  guid,
  type_name,
  prop_values,
  tokenize = 'unicode61'
);

CREATE INDEX idx_elements_storey ON elements(storey_id);
CREATE INDEX idx_elements_guid ON elements(guid);
CREATE INDEX idx_elements_parent ON elements(parent_id);
CREATE INDEX idx_psets_element ON psets(element_id);
CREATE INDEX idx_psets_type ON psets(type_id);
CREATE INDEX idx_props_pset ON props(pset_id);
CREATE INDEX idx_quantities_element ON quantities(element_id);
CREATE INDEX idx_layers_set ON material_layers(set_id);
CREATE INDEX idx_class_element ON classification(element_id);
CREATE INDEX idx_spatial_parent ON spatial(parent_id);
)SQL";

}  // namespace fbv
