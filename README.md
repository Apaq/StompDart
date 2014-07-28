StompDart
=========

A Stomp implementation for Dart heavily inspired by StompJS.

It takes advantage of Dart's Streams and Futures making the API very easy and fluent to use. Furthermore it is very flexible when it comes to the underlying socket technology to use as it exposes an adapter interface making it possible to use WebSocket, SockJS, TCP Socket etc.

Adapter Interface
------------
```
abstract class SocketAdapter {
  void send(data);
  void close();
  Stream<DataEvent> get onMessage;
  Stream<CloseEvent> get onClose;
  Stream<OpenEvent> get onOpen;
}
```
Any extension of the SocketAdapter class is usable by StompDart.

Usage
-------------
```
SocketAdapter socket = ...; <- Any SocketAdapter implementation
Client client = new Client(socket);
client.connect().then((Frame frame) {
  StreamSubscription subscription = client.subscribe("/query/events").listen((Frame frame) {
    // frame has frame.command, frame.body and frame.headers
  });
  
  ...
  //Later on we may wanna cancel the subscription.
  subscription.cancel();
});
```

Example for WebSocket
-------------------
```
import 'package:stompdart/stomp.dart' as Stomp;
import 'package:stompdart/websocketadapter.dart' as StompAdapter;
import 'dart:html'

WebSocket ws = new WebSocket('ws://server');
StompAdapter.WebSocketAdapter adapter = new StompAdapter.WebSocketAdapter(ws);
Stomp.Client client = new Stomp.Client(adapter);
.....
```

Example for SockJS
-------------------
```
import 'package:stompdart/stomp.dart' as Stomp;
import 'package:stompdart/sockjsadapter.dart' as StompAdapter;
import 'package:sockjs_client/sockjs_client.dart' as SockJS;

SockJS.Client sockjs = new SockJS.Client('ws://server);
StompAdapter.WebSocketAdapter adapter = new StompAdapter.WebSocketAdapter(sockjs);
Stomp.Client client = new Stomp.Client(adapter);
...
```


