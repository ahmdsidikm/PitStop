import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static ConnectivityService? _instance;
  static ConnectivityService get instance =>
      _instance ??= ConnectivityService._();
  ConnectivityService._();

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onStatusChange => _controller.stream;

  StreamSubscription? _sub;

  Future<void> init() async {
    // checkConnectivity() sekarang mengembalikan List, bukan 1 item
    final result = await Connectivity().checkConnectivity();
    _isOnline = _isConnected(result);

    _sub = Connectivity().onConnectivityChanged.listen((result) {
      // result di sini juga sudah List<ConnectivityResult>
      final nowOnline = _isConnected(result);
      if (nowOnline != _isOnline) {
        _isOnline = nowOnline;
        _controller.add(_isOnline);
      }
    });
  }

  // ✅ PERUBAHAN: parameter sekarang List<ConnectivityResult>
  bool _isConnected(List<ConnectivityResult> results) {
    // .any() = "apakah ADA SALAH SATU yang memenuhi syarat?"
    return results.any((r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet);
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}