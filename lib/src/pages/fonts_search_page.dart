import 'dart:async';

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';
import 'package:stickers/src/fonts_api/fonts_models.dart';
import 'package:stickers/src/fonts_api/fonts_registry.dart';
import 'package:stickers/src/fonts_api/google_fonts.dart';
import 'package:stickers/src/pages/default_page.dart';
import 'package:stickers/src/pages/fonts_search_delegate.dart';

class FontsSearchPage extends StatefulWidget {
  const FontsSearchPage({super.key});

  @override
  State<FontsSearchPage> createState() => _FontsSearchPageState();
}

class _FontsSearchPageState extends State<FontsSearchPage> {
  Future<GoogleFontsReply>? _future;

  @override
  void initState() {
    _future = getFonts();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultSliverActivity(
      title: AppLocalizations.of(context)!.searchForFonts,
      actions: [
        FutureBuilder(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                return IconButton(
                    onPressed: () {
                      showSearch(
                          context: context,
                          delegate: GoogleFontsSearchDelegate(snapshot.data!.items));
                    },
                    icon: Icon(Icons.search));
              }
              return SizedBox();
            })
      ],
      child: FutureBuilder(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final result = snapshot.data!;
              return ListView.separated(
                separatorBuilder: (ctx, idx) {
                  return SizedBox(
                    height: 8,
                  );
                },
                itemBuilder: (ctx, idx) {
                  return GoogleFontPreview(result.items[idx]);
                },
                itemCount: result.items.length,
              );
            }
            if (snapshot.hasError) {
              print(snapshot.error);
              print(snapshot.stackTrace);
              return Column(
                children: [
                  Text(AppLocalizations.of(context)!.error),
                ],
              );
            }
            return Center(child: CircularProgressIndicator());
          }),
    );
  }
}

class GoogleFontPreview extends StatefulWidget {
  final WebFont font;
  final Future<void> Function(WebFont) loadPreview;

  const GoogleFontPreview(this.font, {super.key, this.loadPreview = downloadAndRegisterFontPreview});

  @override
  State<GoogleFontPreview> createState() => _GoogleFontPreviewState();
}

class _GoogleFontPreviewState extends State<GoogleFontPreview> {
  Future? _future;
  bool _delayOver = false;
  Timer? _previewTimer;

  @override
  void initState() {
    super.initState();
    _schedulePreview();
  }

  void _schedulePreview() {
    _previewTimer?.cancel();
    _future = null;
    _delayOver = false;
    _previewTimer = Timer(const Duration(milliseconds: 300), _loadPreview);
  }

  void _loadPreview() {
    if (!mounted) return;
    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      _previewTimer = Timer(const Duration(milliseconds: 120), _loadPreview);
      return;
    }
    setState(() {
      _delayOver = true;
      _future = widget.loadPreview(widget.font).then((_) => 0);
    });
  }

  @override
  void didUpdateWidget(GoogleFontPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.font.family != widget.font.family) _schedulePreview();
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool inRegistry = FontsRegistry.get(widget.font.family)?.fontFile != null;
    return Opacity(
      opacity: inRegistry ? .7 : 1,
      child: Card(
        child: FutureBuilder(
            future: _future,
            builder: (context, asyncSnapshot) {
              return Stack(
                children: [
                  ListTile(
                    subtitle: inRegistry
                        ? Center(child: Text(AppLocalizations.of(context)!.alreadyDownloaded))
                        : (asyncSnapshot.hasError
                            ? Center(
                                child: Text(AppLocalizations.of(context)!.errorDownloadingPreview))
                            : null),
                    onTap: inRegistry
                        ? null
                        : () async {
                            await showDialog(
                              context: context,
                              builder: (context) => DownloadFontDialog(widget: widget),
                            );
                          },
                    title: Text(
                      widget.font.family,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily:
                            inRegistry ? widget.font.family : "${widget.font.family}-PREVIEW",
                        fontSize: 25,
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    opacity: (!asyncSnapshot.hasData &&
                            _future != null &&
                            _delayOver &&
                            !asyncSnapshot.hasError)
                        ? .7
                        : 0,
                    duration: Duration(milliseconds: 300),
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: CircularProgressIndicator(
                        color: Theme.of(context).colorScheme.onSurface,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                  ),
                ],
              );
            }),
      ),
    );
  }
}

class DownloadFontDialog extends StatefulWidget {
  const DownloadFontDialog({
    super.key,
    required this.widget,
  });

  final GoogleFontPreview widget;

  @override
  State<DownloadFontDialog> createState() => _DownloadFontDialogState();
}

class _DownloadFontDialogState extends State<DownloadFontDialog> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.downloadItem(widget.widget.font.family)),
      actions: [
        TextButton(
            onPressed: _loading
                ? null
                : () {
                    Navigator.of(context).pop();
                  },
            child: Text(AppLocalizations.of(context)!.cancel)),
        ElevatedButton(
            onPressed: _loading
                ? null
                : () async {
                    setState(() {
                      _loading = true;
                    });
                    await downloadAndRegisterFont(widget.widget.font);
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    Navigator.of(context).pop();
                  },
            child: _loading
                ? Text(AppLocalizations.of(context)!.downloading)
                : Text(AppLocalizations.of(context)!.download)),
      ],
    );
  }
}
