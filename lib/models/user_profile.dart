import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String email;
  final String nickname;
  final String nome;
  final String sobrenome;
  final String nomeCompleto;
  final String iniciais;
  final DateTime criadoEm;

  UserProfile({
    required this.uid,
    required this.email,
    required this.nickname,
    required this.nome,
    required this.sobrenome,
    required this.criadoEm,
  })  : nomeCompleto = '$nome $sobrenome',
        iniciais = '${nome.isNotEmpty ? nome[0].toUpperCase() : ''}${sobrenome.isNotEmpty ? sobrenome[0].toUpperCase() : ''}';

  factory UserProfile.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return UserProfile(
      uid: data['uid'] as String,
      email: data['email'] as String,
      nickname: data['nickname'] as String,
      nome: data['nome'] as String,
      sobrenome: data['sobrenome'] as String,
      criadoEm: (data['criadoEm'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'email': email,
      'nickname': nickname,
      'nome': nome,
      'sobrenome': sobrenome,
      'nomeCompleto': nomeCompleto,
      'iniciais': iniciais,
      'criadoEm': Timestamp.fromDate(criadoEm),
      'atualizadoEm': FieldValue.serverTimestamp(),
    };
  }

  // Para exibir em listas ordenadas por sobrenome
  String get nomeFormatado => '$sobrenome, $nome';
}