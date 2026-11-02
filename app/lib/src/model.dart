class PackageSummary {
  PackageSummary({
    required this.path,
    required this.name,
    required this.schema,
    required this.elementCount,
    required this.bytes,
    required this.isZip,
  });

  final String path;
  final String name;
  final String schema;
  final int elementCount;
  final int bytes;
  final bool isZip;
}

class SpatialNode {
  SpatialNode({
    required this.id,
    required this.parentId,
    required this.kind,
    required this.name,
    required this.hasElevation,
    required this.elevation,
  });

  final int id;
  final int parentId;
  final String kind;
  final String name;
  final bool hasElevation;
  final double elevation;
}

class ElementInfo {
  ElementInfo({
    required this.id,
    required this.parentId,
    required this.storeyId,
    required this.ifcClass,
    required this.name,
    required this.tag,
    required this.typeName,
    required this.material,
    required this.guid,
  });

  final int id;
  final int parentId;
  final int storeyId;
  final String ifcClass;
  final String name;
  final String tag;
  final String typeName;
  final String material;
  final String guid;
}

class PropInfo {
  PropInfo({
    required this.pset,
    required this.name,
    required this.valueText,
    required this.source,
  });

  final String pset;
  final String name;
  final String valueText;
  final String source;
}

class QuantityInfo {
  QuantityInfo({
    required this.qset,
    required this.name,
    required this.kind,
    required this.unit,
    required this.value,
  });

  final String qset;
  final String name;
  final String kind;
  final String unit;
  final double value;
}

class ClassInfo {
  ClassInfo({required this.system, required this.code, required this.title});

  final String system;
  final String code;
  final String title;
}

class SpecRow {
  SpecRow({
    required this.storeyName,
    required this.ifcClass,
    required this.typeName,
    required this.material,
    required this.elementCount,
    required this.quantityKind,
    required this.quantitySum,
  });

  final String storeyName;
  final String ifcClass;
  final String typeName;
  final String material;
  final int elementCount;
  final String quantityKind;
  final double? quantitySum;
}

String specCsv(List<SpecRow> rows) {
  final buffer = StringBuffer('storey,class,type,material,count,quantity_kind,quantity_sum\n');
  for (final row in rows) {
    buffer.write(_csv(row.storeyName));
    buffer.write(',');
    buffer.write(_csv(row.ifcClass));
    buffer.write(',');
    buffer.write(_csv(row.typeName));
    buffer.write(',');
    buffer.write(_csv(row.material));
    buffer.write(',');
    buffer.write(row.elementCount);
    buffer.write(',');
    buffer.write(_csv(row.quantityKind));
    buffer.write(',');
    buffer.write(row.quantitySum ?? '');
    buffer.write('\n');
  }
  return buffer.toString();
}

String _csv(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
