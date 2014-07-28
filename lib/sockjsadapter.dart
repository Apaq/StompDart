import 'dart:async' show Stream, StreamSubscription, StreamTransformer, EventSink, Future;
import 'stomp.dart' as Stomp;
import 'package:sockjs_client/sockjs_client.dart' as SockJS;

class SockJSAdapter extends Stomp.SocketAdapter {
  SockJS.Client _client;
  SockJSAdapter(this._client);

  void send(data) {
    this._client.send(data);  
  }

  void close() {
    // SockJS has no close method
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