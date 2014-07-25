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

Example Implementation for WebSocket
-------------------
```
class WebSocketAdapter extends SocketAdapter {
  WebSocket ws;
  WebSocketAdapter(this.ws) {
    ws.binaryType = "arraybuffer";
  }
  
  void send(data) => this.ws.send(data);
  void close() => this.ws.close();
  
  Stream<DataEvent> get onMessage {
    StreamTransformer transformer = new StreamTransformer.fromHandlers(handleData: (MessageEvent value, EventSink<DataEvent> sink) {
      sink.add(new DataEvent(value.data));
    });
    return this.ws.onMessage.transform(transformer);
  }
  
  Stream<CloseEvent> get onClose {
    StreamTransformer transformer = new StreamTransformer.fromHandlers(handleData: (CloseEvent value, EventSink<CloseEvent> sink) {
      sink.add(new CloseEvent(value.reason));
    });
    return this.ws.onClose.transform(transformer);
  }
  
  Stream<OpenEvent> get onOpen {
    StreamTransformer transformer = new StreamTransformer.fromHandlers(handleData: (Event value, EventSink<OpenEvent> sink) {
      sink.add(new OpenEvent());
    });
    return this.ws.onOpen.transform(transformer);
  }
  
}
```

Example Implementation for SockJS
```
class SockJSAdapter extends Stomp.SocketAdapter {
  SockJS.Client _client;
  SockJSAdapter(this._client);
  
  void send(data) {
    this._client.send(data);  
  }
  
  void close() {
    
  }
  
  Stream<Stomp.DataEvent> get onMessage {
    StreamTransformer transformer = new StreamTransformer.fromHandlers(handleData: (SockJS.MessageEvent value, EventSink<Stomp.DataEvent> sink) {
      sink.add(new Stomp.DataEvent(value.data));
    });
    return this._client.onMessage.transform(transformer);
  }
  Stream<Stomp.CloseEvent> get onClose {
    StreamTransformer transformer = new StreamTransformer.fromHandlers(handleData: (SockJS.CloseEvent value, EventSink<Stomp.CloseEvent> sink) {
      sink.add(new Stomp.CloseEvent(value.reason));
    });
    return this._client.onClose.transform(transformer);
  }
  Stream<Stomp.OpenEvent> get onOpen {
    StreamTransformer transformer = new StreamTransformer.fromHandlers(handleData: (var value, EventSink<Stomp.OpenEvent> sink) {
      sink.add(new Stomp.OpenEvent());
    });
    return this._client.onOpen.transform(transformer);
  }
}
```


