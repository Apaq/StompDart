/// A SocketAdapter implementation for SockJS.
library stomdart.sockjs;
import 'dart:async' show Stream, StreamSubscription, StreamTransformer, EventSink, Future;
import 'stomp.dart' as Stomp;
import 'package:sockjs_client/sockjs_client.dart' as SockJS;

/**
 * Adapter for using SockJS as transportlayer.
 * 
 * Example: 
 * ```
 * import 'package:stompdart/stomp.dart' as Stomp;
 * import 'package:stompdart/sockjsadapter.dart' as StompAdapter;
 * import 'package:sockjs_client/sockjs_client.dart' as SockJS;
 * 
 * SockJS.Client sockjs = new SockJS.Client('ws://server);
 * StompAdapter.WebSocketAdapter adapter = new StompAdapter.WebSocketAdapter(sockjs);
 * Stomp.Client client = new Stomp.Client(adapter);
 * ```
 */ 
class SockJSAdapter extends Stomp.SocketAdapter {
  SockJS.Client _client;
  
  // SockJS does not expose the url or host. We accept the host here.
  // Added a pull request for adding the url as a getter: https://github.com/nelsonsilva/sockjs-dart-client/pull/8
  String _host;
  SockJSAdapter(this._client, String host);
  
  SockJSAdapter.fromUrl(String url) {
    this._host = Uri.parse(url).host;
    this._client = new SockJS.Client(url); 
  }

  String getHost() {
    return this._host;
  }
  
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
