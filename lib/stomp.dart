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
  final Logger log = new Logger('Client');
  SocketAdapter _socketAdapter;
  Timer _pinger, _ponger;
  DateTime _serverActivity = new DateTime.now();

  //used to index subscribers
  int _counter = 0;
  bool _connected = false;
  StreamSubscription closeSubscription;


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
  void _transmit(String command, Map headers, [String body=""]) {
    String out = Frame.marshall(command, headers, body);
    this.log.fine(">>>$out");
    // if necessary, split the *STOMP* frame to send it on many smaller *Socket* frames
    while (true) {
      if (out.length > MAX_FRAME_SIZE) {
        this._socketAdapter.send(out.substring(0, MAX_FRAME_SIZE));
        out = out.substring(MAX_FRAME_SIZE);
        this.log.fine("remaining = ${out.length}");
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
      this.log.fine("send ping every ${ttl}ms");
          
      // The `Stomp.setInterval` is a wrapper to handle regular callback
      // that depends on the runtime environment (Web browser or node.js app)
      this._pinger = new Timer.periodic(new Duration(milliseconds: ttl), (Timer timer) {
        this._socketAdapter.send("\n");
        this.log.fine(">>> PING");
      });

    }

    if (this._heartbeatIncoming != 0 && serverOutgoing != null) {
      int ttl = math.max(this._heartbeatIncoming, serverOutgoing);
      this.log.fine("check pong every ${ttl}ms");
      this._ponger = new Timer.periodic(new Duration(milliseconds: ttl), (Timer timer) {
        Duration delta = this._serverActivity.difference(new DateTime.now());
        // We wait twice the TTL to be flexible on window's setInterval calls
        if (delta.inMilliseconds > ttl * 2) {
          this.log.fine("did not receive server activity for the last ${delta}ms");
          this._socketAdapter.close();
        }
      });


    }
  }

  /**
         * [CONNECT Frame](http://stomp.github.com/stomp-specification-1.1.html#CONNECT_or_STOMP_Frame)
         * 
         * The `connect` method accepts different number of arguments and types:
         * `connect(headers, connectCallback)`
         * `connect(headers, connectCallback, errorCallback)`
         * `connect(login, passcode, connectCallback)`
         * `connect(login, passcode, connectCallback, errorCallback)`
         * `connect(login, passcode, connectCallback, errorCallback, host)`
         *
         * The errorCallback is optional and the 2 first forms allow to pass other
         * headers in addition to `client`, `passcode` and `host`.
         */
  Future<Frame> connect([Map headers, String login, String passcode]) {
    Completer<Frame> completer = new Completer();
    this.log.fine("Opening socket...");
    this._socketAdapter.onMessage.listen((DataEvent event) {
      String data;

      if (event.data is ByteBuffer) {
        // the data is stored inside an ByteBuffer, we decode it to get the
        // data as a String
        Uint8List arr = new Uint8List.view(event.data);
        this.log.fine("--- got data length: ${arr.length}");
        //Return a string formed by all the char codes stored in the Uint8array
        data = arr.join();
      } else {
        // take the data directly from the WebSocket `data` field
        data = event.data;
      }


      this._serverActivity = new DateTime.now();
      if (data == "\n") { // heartbeat
        this.log.fine("<<< PONG");
        return;
      }
      this.log.fine("<<< ${data}");
      //Handle STOMP frames received from the server
      for (Frame frame in Frame.unmarshall(data)) {

        // [CONNECTED Frame](http://stomp.github.com/stomp-specification-1.1.html#CONNECTED_Frame)
        switch (frame.command) {
          case "CONNECTED":
            this.log.fine("connected to server ${frame.headers["server"]}");
            this._connected = true;
            this._setupHeartbeat(frame.headers);
            completer.complete(frame);
            break;
          // [MESSAGE Frame](http://stomp.github.com/stomp-specification-1.1.html#MESSAGE)
          case "MESSAGE":
            /**
                     * the `onreceive` callback is registered when the client calls `subscribe()`.
                     * If there is registered subscription for the received message,
                     * we used the default `onreceive` method that the client can set.
                     * This is useful for subscriptions that are automatically created
                     * on the browser side (e.g. [RabbitMQ's temporary
                     * queues](http://www.rabbitmq.com/stomp.html)).
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
              this.log.fine("Unhandled received MESSAGE: ${frame}");
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
            if(this._receiptController.hasListener) {
              this._receiptController.add(frame);
            }
            break;
          case "ERROR":
            completer.completeError(frame);
            break;
          default:
            this.log.fine("Unhandled frame: ${frame}");
            break;
        }
      }

    });


    closeSubscription = this._socketAdapter.onClose.listen((CloseEvent event) {
      this.log.fine(event.reason);
      this._cleanUp();
      completer.completeError(event.reason);
    });
    this._socketAdapter.onOpen.listen((OpenEvent event) {
      this.log.fine("Socket Opened...");
      Map headers = {};
      headers["accept-version"] = "1.2,1.1,1.0";
      headers["heart-beat"] = "${this._heartbeatOutgoing},${this._heartbeatIncoming}";
      this._transmit("CONNECT", headers);
    });
    
    return completer.future;
  }
  
  // [DISCONNECT Frame](http://stomp.github.com/stomp-specification-1.1.html#DISCONNECT)
  void disconnect([Map headers]) {
    this._transmit("DISCONNECT", headers);
    //Discard the onclose callback to avoid calling the errorCallback when
    //the client is properly disconnected.
    this.closeSubscription.cancel().then((value) {
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
    if(this._pinger!=null) this._pinger.cancel();
    if(this._ponger!=null) this._ponger.cancel();
  }
  
  /**
   * [SEND Frame](http://stomp.github.com/stomp-specification-1.1.html#SEND)
   * 
   * `destination` is MANDATORY.
   **/
   void send(String destination, Map headers, String body) {
     headers["destination"] = destination;
     this._transmit("SEND", headers, body);
   }
   
   // [SUBSCRIBE Frame](http://stomp.github.com/stomp-specification-1.1.html#SUBSCRIBE)
   Stream<Frame> subscribe(String destination, [Map headers]) {
     if(headers == null) {
       headers = {};
     }
     // for convenience if the `id` header is not set, we create a new one for this client
     //that will be returned to be able to unsubscribe this subscription
     if(!headers.containsKey("id")) {
      headers["id"] = "sub-${this._counter}";
      this._counter++;
     }
     
     String id = headers["id"];
     StreamController controller = new StreamController(onCancel: () {
       /**
         * [UNSUBSCRIBE Frame](http://stomp.github.com/stomp-specification-1.1.html#UNSUBSCRIBE)
         */
        this._subscriptions.remove(id);
        this._transmit("UNSUBSCRIBE", {id: id});
     }); 
     headers["destination"] = destination;
     this._subscriptions[id] = controller;
     this._transmit("SUBSCRIBE", headers);
     return controller.stream;;
   }

   /**
    * [UNSUBSCRIBE Frame](http://stomp.github.com/stomp-specification-1.1.html#UNSUBSCRIBE)
    * 
    * `id` is MANDATORY.
    * 
    * It is preferable to unsubscribe from a subscription by calling
    * `unsubscribe()` directly on the object returned by `client.subscribe()`:
    * 
    * var subscription = client.subscribe(destination, onmessage);
    * ...
    * subscription.unsubscribe();
    **/
   void unsubscribe(String id) {
     this._subscriptions.remove(id);
     this._transmit("UNSUBSCRIBE", {id: id});
   }
   
   /**
    * [BEGIN Frame](http://stomp.github.com/stomp-specification-1.1.html#BEGIN)
    * 
    * If no transaction ID is passed, one will be created automatically
    **/
   String begin([String transaction]) {
     String txid = transaction == null ? "tx-$this.counter++" : transaction;
     this._transmit("BEGIN", {
       transaction: txid
     });
     return txid;
   }
  
   /**
    * [COMMIT Frame](http://stomp.github.com/stomp-specification-1.1.html#COMMIT)
    * 
    * `transaction` is MANDATORY.
    * It is preferable to commit a transaction by calling `commit()` directly on
    * the object returned by `client.begin()`:
    * 
    * var tx = client.begin(txid);
    * ...
    * tx.commit();
    **/
    void commit(String transaction) {
      this._transmit("COMMIT", {
            transaction: transaction
          });
    }
    
    /**
     * [ABORT Frame](http://stomp.github.com/stomp-specification-1.1.html#ABORT)
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
