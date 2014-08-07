import 'dart:async' show Stream, StreamSubscription, StreamTransformer, EventSink;
import 'stomp.dart' as Stomp;
import 'dart:io';
import 'dart:async';

/**
 * Adapter implementation for Dart Socket connections
 */
class SocketAdapter extends Stomp.SocketAdapter {
  Socket _client;
  Completer closeCompleter = new Completer();
  
  SocketAdapter(this._client);

  void send(String data) {
    this._client.write(data);  
  }

  Future close() {
    return this._client.close();
  }

  Stream<Stomp.DataEvent> get onMessage {
    StreamTransformer transformer = new StreamTransformer.fromHandlers(handleData: (List<int> value, EventSink<Stomp.DataEvent> sink) {
      sink.add(new Stomp.DataEvent(value));
    });
    return this._client.transform(transformer);
  }
  
  Stream<Stomp.CloseEvent> get onClose {
    return this.closeCompleter.future.asStream();
  }
  
  Stream<Stomp.OpenEvent> get onOpen {
    return new Future.value().asStream();
  }
}