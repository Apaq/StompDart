import 'dart:html' show WebSocket, MessageEvent, CloseEvent, Event;
import 'dart:async' show Stream, StreamSubscription, StreamTransformer, EventSink;
import 'stomp.dart';

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