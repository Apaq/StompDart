library stompdart.frame;

import 'dart:convert';

const String STOMP_EOF = '\x00';

/**
 * Definition of a STOMP frame. 
 * 
 * All frames sent back and forth between the server and the client conforms to the structure defined by this class. 
 */
class Frame {
  final String command;
  final Map headers;
  final String body;
  

  /**
   * Creates a new instance of Frame. All arguments must be non-null.
   */
  Frame(this.command, this.headers, this.body) {

    if(this.headers == null) {
      throw new ArgumentError("command must not be null");
    }
    
    if(this.headers == null) {
      throw new ArgumentError("headers must not be null");
    }
    
    if(this.body == null) {
        throw new ArgumentError("body must not be null");
      }
  }


  /**
   * Converts the frame into a string suitable for sending over the wire. 
   * 
   * Remark: The returned string will not contain the EOF mark.
   */
  String toString() {
    List lines = [this.command];
    bool skipContentLength = headers["content-length"] == false;

    if (skipContentLength) {
      headers.remove("content-length");
    }

    headers.forEach((key, value) {
      lines.add("$key:$value");
    });

    if (body.length > 0 && !skipContentLength) {
      var length = UTF8.encoder.convert(this.body).length;
      lines.add("content-length:$length");
    }

    lines.add("\n${this.body}");
    return lines.join("\n");
  }

  /**
   * Unmarshals a String of data containing one STOMP frame.
   */
  static Frame unmarshallSingle(String data) {
    /**
     * search for 2 consecutives LF byte to split the command
     * and headers from the body
     **/
    int divider = data.indexOf("\n\n");
    if(divider < 0) {
      throw new ArgumentError("The data is not a valid Frame.");
    }
    List<String> headerLines = data.substring(0, divider).split("\n");
    String command = headerLines.removeAt(0);
    Map headers = {};

    /**
     * Parse headers in reverse order so that for repeated headers, the 1st
     * value is used
     **/
    for (String line in headerLines.reversed) {
      int idx = line.indexOf(":");
      headers[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
    }

    /**
     * Parse body
     * check for content-length or  topping at the first NULL byte found.
     **/
    String body = "";
    // skip the 2 LF bytes that divides the headers from the body
    int start = divider + 2;
    if (headers.containsKey("content-length")) {
      int len = int.parse(headers["content-length"]);
      body = data.substring(start, start + len);
    } else {
      int chr = null;
      for (int i = start; i < data.length; i++) {
        chr = data.codeUnitAt(i);
        if (chr == 0) {
          break;
        }
        body += new String.fromCharCode(chr);
      }
    }

    return new Frame(command, headers, body);
  }

  /**
   * Unmarshals a list of Frames contained in a String of data.
   */
  static List<Frame> unmarshall(String datas) {
    /**
     * Ugly list comprehension to split and unmarshall *multiple STOMP frames*
     * contained in a *single Socket frame*.
     * The data are splitted when a NULL byte (follwode by zero or many LF bytes) is found
     **/
    List<Frame> frames = [];
    int NULL = 0x00;

    if (datas.length > 0) {
      for (String data in datas.split("//$STOMP_EOF\\n//")) {
        frames.add(unmarshallSingle(data));
      }
    }

    return frames;
  }

  /**
   * Marshal a Frame into a String from command and optionally headers and body.
   */
  static String marshall(String command, {Map headers, String body:""}) {
    if(headers == null) {
      headers = {};
    }
    Frame frame = new Frame(command, headers, body);
    return "${frame.toString()}$STOMP_EOF";
  }

}
