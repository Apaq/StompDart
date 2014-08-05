library stompdart;
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:async' show Timer, Stream, StreamController, StreamSubscription, StreamTransformer, EventSink, Future, Completer;
import 'frame.dart';
import 'package:logging/logging.dart';


/**
 * maximum *WebSocket* frame size sent by the client. If the STOMP frame
 * is bigger than this value, the STOMP frame will be sent using multiple
 * WebSocket frames (default is 16KiB)
 **/
const int MAX_FRAME_SIZE = 16 * 1024;

abstract class SocketAdapter {
  void send(data);
  void close();
  Stream<DataEvent> get onMessage;
  Stream<CloseEvent> get onClose;
  Stream<OpenEvent> get onOpen;
}

class DataEvent {
  var data;

  DataEvent(this.data);

}

class CloseEvent {
  String reason;
  CloseEvent(this.reason);
}

class OpenEvent {

}

class Client {
  final Logger _log = new Logger('Client');
  SocketAdapter _socketAdapter;
  Timer _pinger, _ponger;
  DateTime _serverActivity = new DateTime.now();

  //used to index subscribers
  int _counter = 0;
  bool _connected = false;
  StreamSubscription _closeSubscription;


  // subscription callbacks indexed by subscriber's ID
  Map<String, StreamController<Frame>> _subscriptions = {};

  StreamController<Frame> _receiptController = new StreamController();

  /**
   * Heartbeat properties of the client
   * send heartbeat every 10s by default (value is in ms)
   * expect to receive server heartbeat at least every 10s by default (value in ms)
   **/
  int _heartbeatOutgoing = 10000;
  int _heartbeatIncoming = 10000;

  Client(this._socketAdapter);

  //Base method to transmit any stomp frame
  void _transmit(String command, Map headers, [String body]) {
    body = body == null ? "" : body;
    String out = Frame.marshall(command, headers: headers, body:body);
    this._log.fine(">>>$out");
    // if necessary, split the *STOMP* frame to send it on many smaller *Socket* frames
    while (true) {
      if (out.length > MAX_FRAME_SIZE) {
        this._socketAdapter.send(out.substring(0, MAX_FRAME_SIZE));
        out = out.substring(MAX_FRAME_SIZE);
        this._log.fine("remaining = ${out.length}");
      } else {
        return this._socketAdapter.send(out);
      }
    }
  }

  //Heart-beat negotiation
  void _setupHeartbeat(headers) {
    if (!["1.1", "1.2"].contains(headers["version"])) {
      return;
    }


    /**
       * heart-beat header received from the server looks like:
       * heart-beat: sx, sy
       **/
    List<String> heartbeatInfo = headers["heart-beat"].split(",");
    int serverOutgoing = int.parse(heartbeatInfo[0]),
        serverIncoming = int.parse(heartbeatInfo[1]);

    if (this._heartbeatOutgoing != 0 && serverIncoming != 0) {
      int ttl = math.max(this._heartbeatOutgoing, serverIncoming);
      this._log.fine("send ping every ${ttl}ms");

      // The `Stomp.setInterval` is a wrapper to handle regular callback
      // that depends on the runtime environment (Web browser or node.js app)
      this._pinger = new Timer.periodic(new Duration(milliseconds: ttl), (Timer timer) {
        this._socketAdapter.send("\n");
        this._log.fine(">>> PING");
      });

    }

    if (this._heartbeatIncoming != 0 && serverOutgoing != null) {
      int ttl = math.max(this._heartbeatIncoming, serverOutgoing);
      this._log.fine("check pong every ${ttl}ms");
      this._ponger = new Timer.periodic(new Duration(milliseconds: ttl), (Timer timer) {
        Duration delta = this._serverActivity.difference(new DateTime.now());
        // We wait twice the TTL to be flexible on window's setInterval calls
        if (delta.inMilliseconds > ttl * 2) {
          this._log.fine("did not receive server activity for the last ${delta}ms");
          this._socketAdapter.close();
        }
      });


    }
  }

  /**
   * Sends a [CONNECT Frame](http://stomp.github.com/stomp-specification-1.1.html#CONNECT_or_STOMP_Frame) in order to connect the Stomp Client.
   *
   * All arguments are optional.
   * 
   * This method will return a Future which will complete when a connection has been established. 
   */
  Future<Frame> connect([Map headers, String login, String passcode]) {
    Completer<Frame> completer = new Completer();
    this._log.fine("Opening socket...");
    this._socketAdapter.onMessage.listen((DataEvent event) {
      String data;

      if (event.data is ByteBuffer) {
        // the data is stored inside an ByteBuffer, we decode it to get the
        // data as a String
        Uint8List arr = new Uint8List.view(event.data);
        this._log.fine("--- got data length: ${arr.length}");
        //Return a string formed by all the char codes stored in the Uint8array
        data = arr.join();
      } else {
        // take the data directly from the WebSocket `data` field
        data = event.data;
      }


      this._serverActivity = new DateTime.now();
      if (data == "\n") { // heartbeat
        this._log.fine("<<< PONG");
        return;
      }
      this._log.fine("<<< ${data}");
      //Handle STOMP frames received from the server
      for (Frame frame in Frame.unmarshall(data)) {


        switch (frame.command) {
          case "CONNECTED":
            /**
             * When a [CONNECTED Frame](http://stomp.github.com/stomp-specification-1.1.html#CONNECTED_Frame) is recieved we will complete the waiting Future so
             * the client knows that is has been connected.
             **/
            this._log.fine("connected to server ${frame.headers["server"]}");
            this._connected = true;
            this._setupHeartbeat(frame.headers);
            completer.complete(frame);
            break;
          // [MESSAGE Frame](http://stomp.github.com/stomp-specification-1.1.html#MESSAGE)
          case "MESSAGE":
            /**
             * [MESSAGE Frame](http://stomp.github.com/stomp-specification-1.1.html#MESSAGE)
             * the StreamContrller is registered when the client calls `subscribe()`.
             * If there is registered subscription for the received message,
             * we add the frame to that controller.
             **/
            String subscription = frame.headers["subscription"];
            StreamController<Frame> controller = this._subscriptions[subscription];

            if (controller != null && controller.hasListener) {
              //client = this;
              String messageID = frame.headers["message-id"];
              // add `ack()` and `nack()` methods directly to the returned frame
              // so that a simple call to `message.ack()` can acknowledge the message.
              //frame.ack = (headers = {}) =>
              //  client .ack messageID , subscription, headers
              //frame.nack = (headers = {}) =>
              //  client .nack messageID, subscription, headers
              controller.add(frame);
            } else {
              this._log.fine("Unhandled received MESSAGE: ${frame}");
            }
            break;
          /**
           * [RECEIPT Frame](http://stomp.github.com/stomp-specification-1.1.html#RECEIPT)
           * The client instance can set its `onreceipt` field to a function taking
           * a frame argument that will be called when a receipt is received from
           * the server:
           * 
           * client.onreceipt = function(frame) {
           * receiptID = frame.headers['receipt-id'];
           * ...
           * }
           **/
          case "RECEIPT":
            if (this._receiptController.hasListener) {
              this._receiptController.add(frame);
            }
            break;
          case "ERROR":
            completer.completeError(frame);
            break;
          default:
            this._log.fine("Unhandled frame: ${frame}");
            break;
        }
      }

    });


    _closeSubscription = this._socketAdapter.onClose.listen((CloseEvent event) {
      this._log.fine(event.reason);
      this._cleanUp();
      completer.completeError(event.reason);
    });
    this._socketAdapter.onOpen.listen((OpenEvent event) {
      this._log.fine("Socket Opened...");
      Map headers = {};
      headers["accept-version"] = "1.2,1.1,1.0";
      headers["heart-beat"] = "${this._heartbeatOutgoing},${this._heartbeatIncoming}";
      this._transmit("CONNECT", headers);
    });

    return completer.future;
  }

  /**
   * Send a [DISCONNECT Frame](http://stomp.github.com/stomp-specification-1.1.html#DISCONNECT) in order to tell the server that the client is disconnecting.
   **/
  void disconnect([Map headers]) {
    this._transmit("DISCONNECT", headers);
    //Discard the onclose callback to avoid calling the errorCallback when
    //the client is properly disconnected.
    this._closeSubscription.cancel().then((value) {
      this._socketAdapter.close();
      this._cleanUp();
    });

  }

  /**
   * Clean up client resources when it is disconnected or the server did not
   * send heart beats in a timely fashion
   **/
  void _cleanUp() {
    this._connected = false;
    if (this._pinger != null) this._pinger.cancel();
    if (this._ponger != null) this._ponger.cancel();
  }

  /**
   * Sends a [SEND Frame](http://stomp.github.com/stomp-specification-1.1.html#SEND)
   * 
   * Destination is MANDATORY.
   **/
  void send(String destination, {Map headers, String body, String transactionId}) {
    headers = headers == null ? {} : headers;
    headers["destination"] = destination;
    
    if(transactionId != null) {
      headers["transaction"] = transactionId;
    }
    
    this._transmit("SEND", headers, body);
  }

  /**
    * Sends a [SUBSCRIBE Frame](http://stomp.github.com/stomp-specification-1.1.html#SUBSCRIBE) in order to create a new subscription.
    * 
    * 'destination' is mandatory. 
    * 
    * This method will return a stream. When the stream is cancelled(has no more listeners) an 
    * [UNSUBSCRIBE Frame](http://stomp.github.com/stomp-specification-1.1.html#UNSUBSCRIBE) will be sent in order to unsubscribe the existing subscription.
    **/
  Stream<Frame> subscribe(String destination, [Map headers]) {
    if (headers == null) {
      headers = {};
    }
    // for convenience if the `id` header is not set, we create a new one for this client
    //that will be returned to be able to unsubscribe this subscription
    if (!headers.containsKey("id")) {
      headers["id"] = "sub-${this._counter}";
      this._counter++;
    }

    String id = headers["id"];
    StreamController controller = new StreamController(onCancel: () {
      this._subscriptions.remove(id);
      this._transmit("UNSUBSCRIBE", {
        id: id
      });
    });
    headers["destination"] = destination;
    this._subscriptions[id] = controller;
    this._transmit("SUBSCRIBE", headers);
    return controller.stream;
  }

  /**
    * Sends a [BEGIN Frame](http://stomp.github.com/stomp-specification-1.1.html#BEGIN) which is used for starting a new transaction.
    * If no transaction ID is passed, one will be created automatically. 
    * 
    * Will always return the transaction id.
    **/
  String begin([String transaction]) {
    String txid = transaction == null ? "tx-${this._counter++}" : transaction;
    this._transmit("BEGIN", {
      transaction: txid
    });
    return txid;
  }

  /**
    * Sends a [COMMIT Frame](http://stomp.github.com/stomp-specification-1.1.html#COMMIT) which is used to commit a transaction.
    * 
    * `transaction` is MANDATORY.
    * 
    **/
  void commit(String transaction) {
    this._transmit("COMMIT", {
      transaction: transaction
    });
  }

  /**
     * Send an [ABORT Frame](http://stomp.github.com/stomp-specification-1.1.html#ABORT) which is used to abort a transaction.
     * 
     * `transaction` is MANDATORY.
     **/
  void abort(String transaction) {
    this._transmit("ABORT", {
      transaction: transaction
    });
  }

  void ack(String messageID, String subscription, Map headers) {
    headers["message-id"] = messageID;
    headers["subscription"] = subscription;
    this._transmit("ACK", headers);

  }

  void nack(String messageID, String subscription, Map headers) {
    headers["message-id"] = messageID;
    headers["subscription"] = subscription;
    this._transmit("NACK", headers);
  }
}
