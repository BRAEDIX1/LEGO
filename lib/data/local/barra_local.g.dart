// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'barra_local.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BarraLocalAdapter extends TypeAdapter<BarraLocal> {
  @override
  final int typeId = 32;

  @override
  BarraLocal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BarraLocal(
      tag: fields[0] as String,
      codigo: fields[1] as String,
      lote: fields[2] as String?,
      updatedAt: fields[3] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, BarraLocal obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.tag)
      ..writeByte(1)
      ..write(obj.codigo)
      ..writeByte(2)
      ..write(obj.lote)
      ..writeByte(3)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BarraLocalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
