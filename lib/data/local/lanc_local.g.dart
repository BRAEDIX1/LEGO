// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lanc_local.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LancLocalAdapter extends TypeAdapter<LancLocal> {
  @override
  final int typeId = 42;

  @override
  LancLocal read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LancLocal(
      idLocal: fields[0] as String,
      uid: fields[1] as String,
      codigo: fields[2] as String,
      descricao: fields[3] as String,
      unidade: fields[4] as String,
      quantidade: fields[5] as double,
      prateleira: fields[6] as String,
      cheio: fields[7] as double,
      vazio: fields[8] as double,
      lote: fields[9] as String?,
      tag: fields[10] as String?,
      createdAtLocal: fields[11] as DateTime,
      status: fields[12] as LancStatus,
      errorCode: fields[13] as String?,
      remoteId: fields[14] as String?,
      registro: fields[15] as TipoRegistro,
      volume: fields[16] as double?,
      inventarioId: fields[17] as String?,
      contagemId: fields[18] as String?,
      nickname: fields[19] as String?,
      nomeCompleto: fields[20] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, LancLocal obj) {
    writer
      ..writeByte(21)
      ..writeByte(0)
      ..write(obj.idLocal)
      ..writeByte(1)
      ..write(obj.uid)
      ..writeByte(2)
      ..write(obj.codigo)
      ..writeByte(3)
      ..write(obj.descricao)
      ..writeByte(4)
      ..write(obj.unidade)
      ..writeByte(5)
      ..write(obj.quantidade)
      ..writeByte(6)
      ..write(obj.prateleira)
      ..writeByte(7)
      ..write(obj.cheio)
      ..writeByte(8)
      ..write(obj.vazio)
      ..writeByte(9)
      ..write(obj.lote)
      ..writeByte(10)
      ..write(obj.tag)
      ..writeByte(11)
      ..write(obj.createdAtLocal)
      ..writeByte(12)
      ..write(obj.status)
      ..writeByte(13)
      ..write(obj.errorCode)
      ..writeByte(14)
      ..write(obj.remoteId)
      ..writeByte(15)
      ..write(obj.registro)
      ..writeByte(16)
      ..write(obj.volume)
      ..writeByte(17)
      ..write(obj.inventarioId)
      ..writeByte(18)
      ..write(obj.contagemId)
      ..writeByte(19)
      ..write(obj.nickname)
      ..writeByte(20)
      ..write(obj.nomeCompleto);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LancLocalAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class LancStatusAdapter extends TypeAdapter<LancStatus> {
  @override
  final int typeId = 41;

  @override
  LancStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return LancStatus.pending;
      case 1:
        return LancStatus.synced;
      case 2:
        return LancStatus.error;
      default:
        return LancStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, LancStatus obj) {
    switch (obj) {
      case LancStatus.pending:
        writer.writeByte(0);
        break;
      case LancStatus.synced:
        writer.writeByte(1);
        break;
      case LancStatus.error:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LancStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TipoRegistroAdapter extends TypeAdapter<TipoRegistro> {
  @override
  final int typeId = 43;

  @override
  TipoRegistro read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TipoRegistro.automatico;
      case 1:
        return TipoRegistro.manual;
      default:
        return TipoRegistro.automatico;
    }
  }

  @override
  void write(BinaryWriter writer, TipoRegistro obj) {
    switch (obj) {
      case TipoRegistro.automatico:
        writer.writeByte(0);
        break;
      case TipoRegistro.manual:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TipoRegistroAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
