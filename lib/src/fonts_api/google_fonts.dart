import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:stickers/src/fonts_api/fonts_models.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/globals.dart';
import 'package:stickers/src/api_keys.dart';

String apiURL = "https://www.googleapis.com/webfonts/v1/webfonts";
/*
 * https://developers.google.com/fonts/docs/developer_api/?apix=true
 * webfonts?key=<your_key>[&family=<family>][&subset=<subset>][&capability=<capability>...][&sort=<sort>]
 *    your_key: Your developer API Key.
 *    family: Name of a font family.
 *    subset: Name of a font subset.
 *    category: serif | sans-serif | monospace | display | handwriting
 *    capability: VF | WOFF2.
 *    sort: alpha | date | popularity | style | trending.
 */
Future<GoogleFontsReply> getFonts({String? family, String? category}) async {
  if (fontsKey.isEmpty) {
    debugPrint("Google Fonts API key is missing. Google Fonts will not be available.");
    return GoogleFontsReply(kind: "webfonts#webfontList", items: []);
  }

  File fontsListCache = File("$fontsCacheDir/google_fonts.json");
  if (await fontsListCache.exists()) {
    try {
      return GoogleFontsReply.fromJson(jsonDecode(await fontsListCache.readAsString()));
    } on Exception catch (e, st) {
      debugPrint("Couldn't read font list from cache");
      debugPrint(e.toString());
      debugPrintStack(stackTrace: st);
    }
  }
  Uri uri = Uri.parse(apiURL).replace(
    queryParameters: {
      "key": fontsKey,
      "family": ?family,
      "category": ?category,
    },
  );
  final response = await http.get(uri);
  if (response.statusCode != 200) throw HttpException('Google Fonts returned HTTP ${response.statusCode}');
  final reply = GoogleFontsReply.fromJson(jsonDecode(response.body));
  await fontsListCache.create(recursive: true);
  await fontsListCache.writeAsString(response.body);
  return reply;
}

double totalDownload = 0;

Future<void> downloadAndRegisterFont(WebFont font) async {
  final entry = FontsRegistry.get(font.family) ?? FontsRegistryEntry(font.family, FontType.googleFont);
  await Directory(googleFontsDir).create(recursive: true);
  File dest = File("$googleFontsDir/${font.family}.ttf");
  final result = await http.get(Uri.parse(font.files["regular"] ?? font.files[font.variants.first]!));
  if (result.statusCode != 200) throw HttpException('Font download returned HTTP ${result.statusCode}');
  await dest.writeAsBytes(result.bodyBytes);
  final loader = FontLoader(font.family);
  loader.addFont(Future.value(ByteData.view(result.bodyBytes.buffer)));
  await loader.load();
  entry.fontFile = dest.path;
  FontsRegistry.put(font.family, entry);
  await registerFont(entry);
}

final _previewDownloads = <String, Future<void>>{};

Future<void> downloadAndRegisterFontPreview(WebFont font, {http.Client? client}) {
  return _previewDownloads.putIfAbsent(font.family, () async {
    try {
      await _downloadFontPreview(font, client);
    } finally {
      _previewDownloads.remove(font.family);
    }
  });
}

Future<void> _downloadFontPreview(WebFont font, http.Client? client) async {
  await FontsRegistry.init();
  final existing = FontsRegistry.get(font.family);
  if (existing?.fontFile != null || (existing?.isLoaded == true && existing?.previewFile != null)) return;
  if (existing?.previewFile != null && await File(existing!.previewFile!).exists()) {
    final loader = FontLoader('${font.family}-PREVIEW');
    loader.addFont(Future.value(ByteData.sublistView(await File(existing.previewFile!).readAsBytes())));
    await loader.load();
    existing.isLoaded = true;
    return;
  }

  // Downloading font files for all of these fonts would use up almost 1GB of data, which is why we only download
  // a preview version of the font, capable of displaying only the font name, cutting the total download down to ~35MB
  // This unfortunately means we have to parse CSS as the official API does not provide this feature.
  // In the flutter engine, this preview font is registered as $family-PREVIEW.
  // In the editor plugin, this preview font is not registered at all.
  final uri = Uri.https('fonts.googleapis.com', '/css2', {'family': font.family, 'text': font.family});
  var result = await (client?.get(uri) ?? http.get(uri));
  if (result.statusCode != 200) throw HttpException('Font preview returned HTTP ${result.statusCode}');
  totalDownload += (result.contentLength ?? 0) / 1000.0;

  final regex = RegExp(r"url\((.*?)\)", dotAll: true);
  final match = regex.firstMatch(result.body);
  final fontUrl = match?.group(1)?.trim();

  if (fontUrl == null) throw const FormatException('Missing preview font URL');
  result = await (client?.get(Uri.parse(fontUrl)) ?? http.get(Uri.parse(fontUrl)));
  if (result.statusCode != 200) throw HttpException('Font file returned HTTP ${result.statusCode}');
  totalDownload += (result.contentLength ?? 0) / 1000.0;
  debugPrint("Total: $totalDownload kB");

  debugPrint("Downloaded preview font ${font.family}");

  File dest = File("$fontsCacheDir/${font.family}.ttf");
  await dest.parent.create(recursive: true);
  await dest.writeAsBytes(result.bodyBytes);
  final loader = FontLoader("${font.family}-PREVIEW");
  loader.addFont(Future.value(ByteData.view(result.bodyBytes.buffer)));
  await loader.load();
  final entry = FontsRegistry.get(font.family) ?? FontsRegistryEntry(font.family, FontType.googleFont);
  entry.previewFile = dest.path;
  entry.isLoaded = true;
  FontsRegistry.put(font.family, entry);
}
