import 'package:unittest/unittest.dart';
import 'package:stompdart/stomp.dart';
import 'dart:async';

class MockSocketAdapter extends SocketAdapter {

  StreamController<DataEvent> _messageStream = new StreamController();
  Completer<CloseEvent> closeFuture;
  Future<OpenEvent> openFuture = new Future.delayed(new Duration(milliseconds: 30));
  String lastTransaction;
  bool heartbeatRecieved = false;
  Frame lastFrameRecieved;

  MockSocketAdapter() {
    this.closeFuture = new Completer();
  }

  String getHost() {
    return "server.com";
  }

  void send(data) {
    if (data == "\n") {
      heartbeatRecieved = true;
      return;
    }

    Frame frame = Frame.unmarshallSingle(data);
    this.lastFrameRecieved = frame;

    switch (frame.command) {
      case "CONNECT":
        this._messageStream.add(new DataEvent(Frame.marshall("CONNECTED", headers: {
          "version": "1.1",
          "heart-beat": "1000, 1000"
        })));
        break;
      case "SUBSCRIBE":
        String id = frame.headers["id"];
        String destination = frame.headers["destination"];
        if (destination == "/query/events") {
          this._messageStream.add(new DataEvent(Frame.marshall("MESSAGE", headers: {
            "subscription": id
          }, body: "Развивающий мультик для детей от 11 месяцев до 3 лет")));
        }
        break;
      case "SEND":
        String tx = frame.headers["transaction"];
        if (tx != null) {
          lastTransaction = tx;
        }
        break;
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
      MockSocketAdapter adapter = new MockSocketAdapter();
      Client client = new Client(adapter);
      Future<Frame> future = client.connect();
      expect(future.then((frame) {
        expect("CONNECT", adapter.lastFrameRecieved.command);
        expect(adapter.getHost(), adapter.lastFrameRecieved.headers["host"]);

        expect("CONNECTED", frame.command);
      }), completes);


    });

    test('client can connect with specified host', () {
      MockSocketAdapter adapter = new MockSocketAdapter();
      Client client = new Client(adapter);
      Future<Frame> future = client.connect(host: "burgerking.com");
      expect(future.then((frame) {
        expect("burgerking.com", adapter.lastFrameRecieved.headers["host"]);
        expect("CONNECTED", frame.command);
      }), completes);


    });
    
    test('client can connect with specified host via headers', () {
          MockSocketAdapter adapter = new MockSocketAdapter();
          Client client = new Client(adapter);
          Future<Frame> future = client.connect(headers: {"host":"burgerking.com"});
          expect(future.then((frame) {
            expect("burgerking.com", adapter.lastFrameRecieved.headers["host"]);
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
          expect("Развивающий мультик для детей от 11 месяцев до 3 лет", messageFrame.body);
        });
        return Future.wait([future]);

      }), completes);


    });

    test('begin generates id', () {
      MockSocketAdapter adapter = new MockSocketAdapter();
      Client client = new Client(adapter);
      Future<Frame> future = client.connect();
      expect(future.then((frame) {
        String tx = client.begin();
        expect(tx, "tx-0");

        return Future.wait([future]);
      }), completes);
    });

    test('client can commit transaction', () {
      MockSocketAdapter adapter = new MockSocketAdapter();
      Client client = new Client(adapter);
      Future<Frame> future = client.connect();
      expect(future.then((frame) {

        String tx = client.begin();
        client.send("/tx", transactionId: tx);

        expect(tx, adapter.lastTransaction);

        return Future.wait([future]);

      }), completes);
    });

    test('heartbeat is send', () {
      MockSocketAdapter adapter = new MockSocketAdapter();
      Client client = new Client(adapter);
      client.heartbeatIncoming = 1000;
      client.heartbeatOutgoing = 1000;
      Future<Frame> future = client.connect();
      expect(future.then((frame) {

        Future delay = new Future.delayed(new Duration(milliseconds: 1000));
        delay.then((value) {
          expect(true, adapter.heartbeatRecieved);
        });


        return Future.wait([delay]);

      }), completes);
    });

  });
}
