/// A SocketAdapter implementation for Dart's WebSockets.
library stomdart.websocket;
import 'dart:html' show WebSocket, MessageEvent, CloseEvent, Event;
import 'dart:async' show Stream, StreamSubscription, StreamTransformer, EventSink, Future;
import 'stomp.dart' as Stomp;

/**
 * Adapter for using Websocket as transport layer.
 * 
 * Example:
 * ```
 * import 'package:stompdart/stomp.dart' as Stomp;
 * import 'package:stompdart/websocketadapter.dart' as StompAdapter;
 * import 'dart:html'
 * 
 * WebSocket ws = new WebSocket('ws://server');
 * StompAdapter.WebSocketAdapter adapter = new StompAdapter.WebSocketAdapter(ws);
 * Stomp.Client client = new Stomp.Client(adapter);
 * ```
 */
class WebSocketAdapter extends Stomp.SocketAdapter {
  WebSocket ws;
  WebSocketAdapter(this.ws) {
    ws.binaryType = "arraybuffer";
  }

  String getHost() {
    return Uri.parse(this.ws.url).host;
  }
  
  void send(data) => this.ws.send(data);
  void close() {
    this.ws.close();
  }

  Stream<Stomp.DataEvent> get onMessage {
    StreamTransformer transformer = new StreamTransformer.fromHandlers(handleData: (MessageEvent value, EventSink<Stomp.DataEvent> sink) {
      sink.add(new Stomp.DataEvent(value.data));
    });
    return this.ws.onMessage.transform(transformer);
  }

  Stream<Stomp.CloseEvent> get onClose {
    StreamTransformer transformer = new StreamTransformer.fromHandlers(handleData: (CloseEvent value, EventSink<Stomp.CloseEvent> sink) {
      sink.add(new Stomp.CloseEvent(value.reason));
    });
    return this.ws.onClose.transform(transformer);
  }

  Stream<Stomp.OpenEvent> get onOpen {
    StreamTransformer transformer = new StreamTransformer.fromHandlers(handleData: (Event value, EventSink<Stomp.OpenEvent> sink) {
      sink.add(new Stomp.OpenEvent());
    });
    return this.ws.onOpen.transform(transformer);
  }

}
