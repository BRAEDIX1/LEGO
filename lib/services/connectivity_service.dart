// lib/services/connectivity_service.dart
import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:lego/services/sync_service.dart';

class ConnectivityService {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  void start() {
    _sub ??= Connectivity().onConnectivityChanged.listen((results) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final isOffline = results.every((r) => r == ConnectivityResult.none);
      if (isOffline) {
        SyncService.cancel(uid);
        return;
      }

      await SyncService.runOnce(uid);
      SyncService.schedule(uid);
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      SyncService.cancel(uid);
    }
  }
}
