import 'package:unittest/unittest.dart';
import '../lib/stomp.dart';
import '../lib/frame.dart';
import 'dart:async';

class MockSocketAdapter extends SocketAdapter {

  StreamController<DataEvent> _messageStream = new StreamController();
  Completer<CloseEvent> closeFuture;
  Future<OpenEvent> openFuture = new Future.delayed(new Duration(seconds: 2));
  
  MockSocketAdapter() {
    this.closeFuture = new Completer();
  }
  
  void send(data) {
    Frame frame = Frame.unmarshallSingle(data);
    
    switch(frame.command) {
      case "CONNECT":
        this._messageStream.add(new DataEvent(Frame.marshall("CONNECTED", {})));
        break;
      case "SUBSCRIBE":
        String id = frame.headers["id"];
        this._messageStream.add(new DataEvent(Frame.marshall("MESSAGE", {"subscription": id})));
    }
    
  }
  
  void close() {
    this.closeFuture.complete();
  }
    
  Stream<DataEvent> get onMessage {
    return this._messageStream.stream;
  }
  
  Stream<CloseEvent> get onClose {
    return closeFuture.future.asStream();
  }
  
  Stream<OpenEvent> get onOpen {
    return openFuture.asStream();
  }
}

void main() {
  group("Client Test: ", () {
    
    
    test('client can connect', () {
      SocketAdapter adapter = new MockSocketAdapter();
      Client client = new Client(adapter);
      Future<Frame> future = client.connect();
      expect(future.then((frame) {
        expect("CONNECTED", frame.command);
      }), completes);

      
    });
    
    test('client can subscribe', () {
          SocketAdapter adapter = new MockSocketAdapter();
          Client client = new Client(adapter);
          Future<Frame> future = client.connect();
          expect(future.then((frame) {
            
            Stream<Frame> stream = client.subscribe("/query/events");
            Future future = stream.elementAt(0);
            future.then((messageFrame) {
              expect("MESSAGE", messageFrame.command);
              
            });
            return Future.wait([future]);
            
          }), completes);

          
        });
    
  });
}