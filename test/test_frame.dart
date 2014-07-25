import 'package:unittest/unittest.dart';
import '../lib/frame.dart';

void main() {
  group("Frame Test", () {
    
    test('marshall a CONNECT frame', () =>
      expect("CONNECT\nlogin:john\npasscode:doe\n\n$STOMP_EOF", 
        Frame.marshall("CONNECT", {"login":"john","passcode":"doe"}))
      
    );
    
    test("marshall a SEND frame", () =>
      expect("SEND\ndestination:/queue/test\ncontent-length:13\n\nhello, world!$STOMP_EOF", 
        Frame.marshall("SEND", {"destination":"/queue/test"}, "hello, world!"))
    );

    test("marshall a SEND frame without content-length", () =>
      expect("SEND\ndestination:/queue/test\n\nhello, world!$STOMP_EOF", 
        Frame.marshall("SEND", {"destination":"/queue/test", "content-length": false}, "hello, world!"))
    );
    
    test("unmarshall a CONNECTED frame", () {
      String data = "CONNECTED\nsession-id: 1234\n\n$STOMP_EOF";
      Frame frame = Frame.unmarshall(data)[0];
      expect("CONNECTED", frame.command);
      expect({"session-id": "1234"}, frame.headers);
      expect("", frame.body);
    });
    
    test("unmarshall a RECEIVE frame", () {
      String data = "RECEIVE\nfoo: abc\nbar: 1234\n\nhello, world!$STOMP_EOF";
      Frame frame = Frame.unmarshall(data)[0];
      expect("RECEIVE", frame.command);
      expect({"foo": "abc", "bar": "1234"}, frame.headers);
      expect("hello, world!", frame.body);
    });
    
    test("unmarshall should not include the null byte in the body", () {
      String body1 = 'Just the text please.',
        body2 = 'And the newline\n',
        msg = "MESSAGE\ndestination: /queue/test\nmessage-id: 123\n\n";

        expect(body1, Frame.unmarshall("$msg$body1$STOMP_EOF")[0].body);
        expect(body2, Frame.unmarshall("$msg$body2$STOMP_EOF")[0].body);
        });

    
    test("unmarshall should support colons (:) in header values", () {
      String dest = 'foo:bar:baz',
        msg = "MESSAGE\ndestination: $dest\nmessage-id: 456\n\n\0";
  
      expect(dest, Frame.unmarshall(msg)[0].headers["destination"]);
    });
    
    test("only the 1st value of repeated headers is used", () {
      expect('World', Frame.unmarshall("MESSAGE\ndestination: /queue/test\nfoo:World\nfoo:Hello\n\n$STOMP_EOF")[0].headers["foo"]);
    });
    
  });
}