import 'dart:async' show Stream, StreamSubscription, StreamTransformer, EventSink;
import 'stomp.dart' as Stomp;
import 'dart:io';
import 'dart:async';

/**
 * The adapter interface for the transport layer. The STOMP client only knows of this interface, not of the underlying transport technology. 
 * This makes is possible to adapt different transport layers to be used by the STOMP client.
 * 
 * WebSocketAdapter and SockJSAdapter are examples of adapter transport layer to be used by the STOMP client but any implementation of this interface can be used by the STOMP client.
 */ 
class SocketAdapter extends Stomp.SocketAdapter {
  Socket _client;
  Completer closeCompleter = new Completer();
  
  SocketAdapter(this._client);

  void send(String data) {
    this._client.write(data);  
  }

  Future close() {
    return this._client.close();;
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