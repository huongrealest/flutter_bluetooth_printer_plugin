part of flutter_bluetooth_printer;

class Generator {
  List<int> reset() {
    List<int> bytes = [];
    bytes += cInit.codeUnits;
    return bytes;
  }

  List<int> _intLowHigh(int value, int bytesNb) {
    final dynamic maxInput = 256 << (bytesNb * 8) - 1;

    if (bytesNb < 1 || bytesNb > 4) {
      throw Exception('Can only output 1-4 bytes');
    }
    if (value < 0 || value > maxInput) {
      throw Exception(
          'Number is too large. Can only output up to $maxInput in $bytesNb bytes');
    }

    final List<int> res = <int>[];
    int buf = value;
    for (int i = 0; i < bytesNb; ++i) {
      res.add(buf % 256);
      buf = buf ~/ 256;
    }
    return res;
  }

  Future<List<int>> rasterImage({
    required Uint8List bytes,
    required int dotsPerLine,
  }) async {
    // need to convert to JPG
    // iOS issue, when using PNG the output is broken

    final newBytes = img.encodeJpg(img.decodePng(bytes)!);
    img.Image src = img.decodeJpg(newBytes)!;
    src = img.copyResize(
      src,
      width: dotsPerLine,
      maintainAspect: true,
      backgroundColor: img.ColorRgba8(255, 255, 255, 255),
      interpolation: img.Interpolation.cubic,
    );
    src = img.grayscale(src);

    final int widthPx = src.width;
    final int widthBytes = widthPx ~/ 8;
    final int heightPx = src.height;

    final list = _toRasterFormat(src);

    const int densityByte = 0;
    final List<int> header = <int>[
      ...cRasterImg2.codeUnits,
    ];
    header.add(densityByte);
    header.addAll(_intLowHigh(widthBytes, 2)); // xL xH
    header.addAll(_intLowHigh(heightPx, 2));

    return <int>[
      ...header,
      ...list,
    ];
  }

  /// Image rasterization
  List<int> _toRasterFormat(img.Image imgSrc) {
    final img.Image image = img.Image.from(imgSrc); // make a copy
    final int widthPx = image.width;
    final int heightPx = image.height;

    img.grayscale(image);
    img.invert(image);

    // R/G/B channels are same -> keep only one channel
    final List<int> oneChannelBytes = [];
    final List<int> buffer = image.getBytes(order: img.ChannelOrder.rgba);
    for (int i = 0; i < buffer.length; i += 4) {
      oneChannelBytes.add(buffer[i]);
    }

    // Add some empty pixels at the end of each line (to make the width divisible by 8)
    if (widthPx % 8 != 0) {
      final targetWidth = (widthPx + 8) - (widthPx % 8);
      final missingPx = targetWidth - widthPx;
      final extra = Uint8List(missingPx);
      for (int i = 0; i < heightPx; i++) {
        final pos = (i * widthPx + widthPx) + i * missingPx;
        oneChannelBytes.insertAll(pos, extra);
      }
    }

    // Pack bits into bytes
    return _packBitsIntoBytes(oneChannelBytes);
  }

  /// Merges each 8 values (bits) into one byte
  List<int> _packBitsIntoBytes(List<int> bytes) {
    const pxPerLine = 8;
    final List<int> res = <int>[];
    const threshold = 256 * 0.5; // set the greyscale -> b/w threshold here
    for (int i = 0; i < bytes.length; i += pxPerLine) {
      int newVal = 0;
      for (int j = 0; j < pxPerLine; j++) {
        newVal = _transformUint32Bool(
          newVal,
          pxPerLine - j,
          bytes[i + j] > threshold,
        );
      }
      res.add(newVal ~/ 2);
    }
    return res;
  }

  /// Replaces a single bit in a 32-bit unsigned integer.
  int _transformUint32Bool(int uint32, int shift, bool newValue) {
    return ((0xFFFFFFFF ^ (0x1 << shift)) & uint32) |
        ((newValue ? 1 : 0) << shift);
  }

  Future<img.Image> optimizeImage({
    required Uint8List bytes,
    required int dotsPerLine,
  }) async {
    img.Image src = img.decodeJpg(bytes)!;
    src = img.grayscale(src);

    final w = src.width;
    final h = src.height;

    final res = img.Image(width: w, height: h);
    for (int y = 0; y < h; ++y) {
      for (int x = 0; x < w; ++x) {
        final pixel = src.getPixelSafe(x, y);
        final lum = img.getLuminanceRgb(pixel.r, pixel.g, pixel.b);

        img.Color c;
        final l = lum / 255;
        if (l > 0.8) {
          c = img.ColorUint8.rgb(255, 255, 255);
        } else {
          c = img.ColorUint8.rgb(0, 0, 0);
        }

        res.setPixel(x, y, c);
      }
    }

    src = res;
    src = img.copyResize(
      src,
      width: dotsPerLine,
      maintainAspect: true,
    );

    return src;
  }

  Future<List<int>> _encodeX(Map<String, dynamic> arg) async {
    final dotsPerLine = arg['dotsPerLine'];
    final pngBytes = arg['bytes'];

    return rasterImage(
      bytes: pngBytes,
      dotsPerLine: dotsPerLine,
    );
  }

  Future<List<int>> encode({
    required Uint8List bytes,
    required int dotsPerLine,
    required bool useImageRaster,
  }) {
    final arg = {
      'bytes': bytes,
      'dotsPerLine': dotsPerLine,
      'useImageRaster': useImageRaster,
    };

    return compute(_encodeX, arg);
  }
}
