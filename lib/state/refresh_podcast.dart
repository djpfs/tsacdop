import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_isolate/flutter_isolate.dart';
import 'package:tsacdop/local_storage/key_value_storage.dart';
import 'package:tsacdop/local_storage/sqflite_localpodcast.dart';

import '../type/podcastlocal.dart';

enum RefreshState { none, fetch, error }

class RefreshItem {
  String title;
  RefreshState refreshState;
  RefreshItem(this.title, this.refreshState);
}

class RefreshWorker extends ChangeNotifier {
  FlutterIsolate refreshIsolate;
  ReceivePort receivePort;
  SendPort refreshSendPort;

  RefreshItem _currentRefreshItem = RefreshItem('', RefreshState.none);
  bool _complete = false;
  RefreshItem get currentRefreshItem => _currentRefreshItem;
  bool get complete => _complete;

  bool _created = false;

  Future<void> _createIsolate() async {
    receivePort = ReceivePort();
    refreshIsolate = await FlutterIsolate.spawn(
        refreshIsolateEntryPoint, receivePort.sendPort);
  }

  void _listen() {
    receivePort.distinct().listen((message) {
      if (message is List) {
        _currentRefreshItem =
            RefreshItem(message[0], RefreshState.values[message[1]]);
        notifyListeners();
      } else if (message is String && message == "done") {
        _currentRefreshItem = RefreshItem('', RefreshState.none);
        _complete = true;
        notifyListeners();
        refreshIsolate?.kill();
        refreshIsolate = null;
        _created = false;
      }
    });
  }

  Future<void> start() async {
    if (!_created) {
      _complete = false;
      _createIsolate();
      _listen();
      _created = true;
    }
  }

  void dispose() {
    refreshIsolate?.kill();
    refreshIsolate = null;
    super.dispose();
  }
}

Future<void> refreshIsolateEntryPoint(SendPort sendPort) async {
  KeyValueStorage refreshstorage = KeyValueStorage(refreshdateKey);
  await refreshstorage.saveInt(DateTime.now().millisecondsSinceEpoch);
  var dbHelper = DBHelper();
  List<PodcastLocal> podcastList = await dbHelper.getPodcastLocalAll();
  //int i = 0;
  await Future.forEach<PodcastLocal>(podcastList, (podcastLocal) async {
    sendPort.send([podcastLocal.title, 1]);
    await dbHelper.updatePodcastRss(podcastLocal);
    print('Refresh ' + podcastLocal.title);
  });

  // KeyValueStorage refreshcountstorage = KeyValueStorage('refreshcount');
//  await refreshcountstorage.saveInt(i);
  sendPort.send("done");
}
